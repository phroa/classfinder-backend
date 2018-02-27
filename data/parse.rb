require 'cgi'
require 'fileutils'
require 'nokogiri'

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

contents = File.read 'index.html'

index = Nokogiri::HTML::Document.parse contents

all_terms = (index .xpath("//select[@name='term']/option/@value")
               .map(&:value)
               .map do |term|
               Term.new(term, term[0..3].to_i, TERM_MAP[term[4..6]], false)
             end)

current_term = (index .xpath("//select[@name='term']/option[@selected]/@value")
                  .map(&:value)
                  .map do |term|
                  Term.new(term, term[0..3].to_i, TERM_MAP[term[4..6]], true)
                end)[0]

all_terms.find(current_term).first.current = true

all_attributes = (index .xpath("//select[@name='sel_gur']/option/text()")
                    .drop(1)
                    .map(&:text)
                    .map(&:strip)
                    .map do |x|
                    Attribute.new(*x.split(" - "), x.include?('GUR'))
                  end)

all_subjects = (index .xpath("//select[@name='sel_subj']/option/text()")
                  .drop(1)
                  .map(&:text)
                  .map(&:strip)
                  .map do |x|
                  Subject.new(*x.split(" - "))
                end)

all_instructors = (index .xpath("//select[@name='sel_inst']/option")
                     .drop(1)
                     .map do |x|
                     Instructor.new(x.attr(:value), *x.text.strip.split(', '))
                   end)

all_terms.each do |term|
  FileUtils.mkdir_p "/data/cache/#{term.code}"

  Dir.chdir "/data/cache/#{term.code}" do
    all_subjects.each do |subject|
      unless File.exists? "#{CGI.escape(subject.code)}.html"
        `curl -o "#{CGI.escape(subject.code)}.html" 'https://admin.wwu.edu/pls/wwis/wwsktime.ListClass'\
          -H 'Host: admin.wwu.edu' --compressed\
          -H 'Content-Type: application/x-www-form-urlencoded'\
          --data 'sel_subj=dummy&sel_subj=dummy&sel_gur=dummy&sel_gur=dummy&sel_day=dummy&sel_open=dummy&sel_crn=&term=#{CGI.escape(term.code)}&sel_gur=All&sel_subj=#{CGI.escape(subject.code)}&sel_inst=ANY&sel_crse=&begin_hh=0&begin_mi=A&end_hh=0&end_mi=A&sel_cdts=%25'`
      end
    end
  end
end

#
