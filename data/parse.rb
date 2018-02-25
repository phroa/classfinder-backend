require 'nokogiri'

TERM_MAP = {
  '10' => 'Winter',
  '20' => 'Spring',
  '30' => 'Summer',
  '40' => 'Fall',
}

Term = Struct.new :year, :month, :current
Attribute = Struct.new :code, :desc, :gur
Subject = Struct.new :code, :desc
Instructor = Struct.new :code, :last, :first

contents = File.read 'index.html'

doc = Nokogiri::HTML::Document.parse contents

all_terms = (doc.xpath("//select[@name='term']/option/@value").map(&:value).map do |term|
               Term.new(term[0..3].to_i, TERM_MAP[term[4..6]], false)
             end)

current_term = (doc.xpath("//select[@name='term']/option[@selected]/@value").map(&:value).map do |term|
                  Term.new(term[0..3].to_i, TERM_MAP[term[4..6]], true)
                end)[0]

all_terms.find(current_term).first.current = true

all_attributes = (doc.xpath("//select[@name='sel_gur']/option/text()").drop(1).map(&:text).map(&:strip).map do |x|
                    Attribute.new(*x.split(" - "), x.include?('GUR'))
                  end)

all_subjects = (doc.xpath("//select[@name='sel_subj']/option/text()").drop(1).map(&:text).map(&:strip).map do |x|
                  Subject.new(*x.split(" - "))
                end)

all_instructors = (doc.xpath("//select[@name='sel_inst']/option").drop(1).map do |x|
                     Instructor.new(x.attr(:value), *x.text.strip.split(', '))
                   end)
