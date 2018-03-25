require 'cgi'
require 'date'
require 'fileutils'
require 'nokogiri'
require 'time'

TERM_MAP = {
  '10' => 'Winter',
  '20' => 'Spring',
  '30' => 'Summer',
  '40' => 'Fall',
}
TERM_MAP.merge!(TERM_MAP.invert)

Term = Struct.new :code, :year, :quarter, :current
Attribute = Struct.new :code, :desc, :gur
Subject = Struct.new :code, :desc
Instructor = Struct.new :code, :last, :first
Location = Struct.new :building, :room
Course = Struct.new :code,
                    :subject,
                    :number,
                    :crn,
                    :title,
                    :attributes,
                    :location,
                    :times,
                    :days,
                    :capacity,
                    :enrolled,
                    :available,
                    :instructor,
                    :credits,
                    :fees,
                    :status do
  def add_time! timestring
    self[:times] ||= {}

    days, times, half = timestring.split
    s, e = times.split('-').map(&Time.method(:parse).to_proc)

    if half == 'pm'
      e += 3600 * 12
      s += 3600 * 12 if s.hour < 8
    end

    days.each_char do |day|
      self[:times][day] = s..e
    end
  end
end

contents = File.read 'index.html'

index = Nokogiri::HTML::Document.parse contents

all_terms = (index.xpath("//select[@name='term']/option/@value")
               .map(&:value)
               .map do |term|
               Term.new(term, term[0..3].to_i, TERM_MAP[term[4..6]], false)
             end)

current_term = (index.xpath("//select[@name='term']/option[@selected]/@value")
                  .map(&:value)
                  .map do |term|
                  Term.new(term, term[0..3].to_i, TERM_MAP[term[4..6]], true)
                end)[0]

all_terms.find(current_term).first.current = true

all_attributes = (index.xpath("//select[@name='sel_gur']/option/text()")
                    .drop(1)
                    .map(&:text)
                    .map(&:strip)
                    .map do |attribute|
                    Attribute.new(*attribute.split(" - "), attribute.include?('GUR'))
                  end)

all_subjects = (index.xpath("//select[@name='sel_subj']/option/text()")
                  .drop(1)
                  .map(&:text)
                  .map(&:strip)
                  .map do |attribute|
                  Subject.new(*attribute.split(" - "))
                end)

all_instructors = (index.xpath("//select[@name='sel_inst']/option")
                     .drop(1)
                     .map do |attribute|
                     Instructor.new(attribute.attr(:value), *attribute.text.strip.split(', '))
                   end)

all_courses = {}

all_terms.each do |term|
  FileUtils.mkdir_p "/data/cache/#{term.code}"

  all_courses[term] = {}

  Dir.chdir "/data/cache/#{term.code}" do
    all_subjects.each do |subject|
      unless File.exists? "#{CGI.escape(subject.code)}.html"
        `curl -o "#{CGI.escape(subject.code)}.html" 'https://admin.wwu.edu/pls/wwis/wwsktime.ListClass'\
          -H 'Host: admin.wwu.edu' --compressed\
          -H 'Content-Type: application/attribute-www-form-urlencoded'\
          --data 'sel_subj=dummy&sel_subj=dummy&sel_gur=dummy&sel_gur=dummy&sel_day=dummy&sel_open=dummy&sel_crn=&term=#{CGI.escape(term.code)}&sel_gur=All&sel_subj=#{CGI.escape(subject.code)}&sel_inst=ANY&sel_crse=&begin_hh=0&begin_mi=A&end_hh=0&end_mi=A&sel_cdts=%25'`
      end

      all_courses[term][subject] = []

      subject_html = Nokogiri::HTML::Document.parse(File.read("#{CGI.escape(subject.code)}.html"))

      cells = subject_html
                .css('table')[1]
                .css('td')
                .drop(10)

      while cells.any?
        course = Course.new

        course.status = cells.shift.text.strip || nil

        course.subject = subject
        course.code = cells.shift.text

        # Some courses are like 197L or 491X, only .to_i if it's possible to do so
        course.number = course.code.split[1]
        course.number = course.number.to_i if course.number.to_i.to_s == course.number

        course.title = cells.shift.text
        course.crn = cells.shift.xpath('input').attr('value').value.to_i
        course.capacity = cells.shift.text.to_i
        course.enrolled = cells.shift.text.to_i
        course.available = cells.shift.text.to_i

        ilast, ifirst = cells.shift.text.split(', ')
        course.instructor = (all_instructors.find do |instructor|
                               instructor.first == ifirst && instructor.last == ilast
                             end)

        sday, eday = (cells.shift.text.split('-').map do |range|
                        Date.new(term.year, *range.split('/').map(&:to_i))
                      end)
        course.days = sday..eday

        cells.shift

        course.attributes = (cells.shift.text.split.map do |code|
                               all_attributes.find do |attribute|
                                 attribute.code == code
                               end
                             end)

        course.add_time! cells.shift.text.strip

        building, room = cells.shift.text.gsub(/&nbsp/, '').split
        course.location = Location.new(building, room.to_i)

        credit_range = cells.shift.text.split('-').map(&:to_i)
        if credit_range.size == 1
          course.credits = credit_range[0]
        else
          course.credits = credit_range[0]..credit_range[1]
        end

        course.fees ||= []
        course.fees << cells.shift.text.strip # last cell

        # empty row; divider between courses
        if cells.take(8).all? { |cell| cell.children.empty? }
          cells = cells.drop(8)

          all_courses[term][subject] << course

          # for next loop run
          course = Course.new
        end
      end
    end
  end
end
