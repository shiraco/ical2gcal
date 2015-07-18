# coding: utf-8
require 'icalendar'
require 'dotenv'

Dotenv.load
ARIEL_URL = ENV['ARIEL_URL']
ARIEL_ID = ENV['ARIEL_ID']
ARIEL_USER_ID = ENV['ARIEL_USER_ID']
ARIEL_PASSWORD = ENV['ARIEL_PASSWORD']

class ARIEL
  def initialize
    @agent = Mechanize.new
    @agent.user_agent_alias = 'Windows IE 7'
    @agent.get(ARIEL_URL)
    @agent.page.form_with(:name => 'loginForm') do |form|
      form.field_with(:name => 'loginName').value = ARIEL_USER_ID
      form.field_with(:name => 'password' ).value = ARIEL_PASSWORD
      form.click_button
    end
  end
  def ical
    ical = @agent.get("#{ARIEL_URL}#{ARIEL_ID}/schedule/view?aqua_format=ical&exa=ical").body
    Icalendar.parse(ical).first
  end
end

ical = ARIEL.new.ical
File.write("calendar.ics", ical)
