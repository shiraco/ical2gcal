# coding: utf-8
require 'google/api_client'
require 'icalendar'
require 'dotenv'

Dotenv.load
SECRET_KEY_PATH = ENV['SECRET_KEY_PATH']
SECRET_KEY_PASSWORD = ENV['SECRET_KEY_PASSWORD']
CALENDAR_ID = ENV['CALENDAR_ID']
SERVICE_ACCOUNT_EMAIL = ENV['SERVICE_ACCOUNT_EMAIL']
APPLICATION_NAME = ENV['APPLICATION_NAME']
TERM_MONTHS = 3

class Gcal

  attr_reader :old_events_count, :new_events_count

  def initialize
    # Initialize the API
    @client = Google::APIClient.new(:application_name => APPLICATION_NAME)

    # 認証
    signing_key = Google::APIClient::KeyUtils.load_from_pkcs12(SECRET_KEY_PATH, SECRET_KEY_PASSWORD)
    @client.authorization = Signet::OAuth2::Client.new(
      :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
      :audience => 'https://accounts.google.com/o/oauth2/token',
      :scope => 'https://www.googleapis.com/auth/calendar',  #
      :issuer => SERVICE_ACCOUNT_EMAIL,
      :signing_key => signing_key)
    @client.authorization.fetch_access_token!

    # calendar_api 取得
    @calendar_api = @client.discovered_api('calendar', 'v3')
  end

  def set_term(today, term_months)

    s = Date.new(today.year, today.month, 1)
    s = (s << 5) # TODO remove
    e = (s >> term_months) - 1

    @time_min = Time.local(s.year, s.month, s.day, 0, 0, 0)
    @time_max = Time.local(e.year, e.month, e.day, 23, 59, 59)

  end

  def delete(time_min = @time_min, time_max = @time_max)

    old_events_per_page = @client.execute(:api_method => @calendar_api.events.list,
                                          :parameters =>  {'calendarId' => CALENDAR_ID,
                                                           'timeMin' => time_min.iso8601,
                                                           'timeMax' => time_max.iso8601})

    old_events = []
    while true
      old_events.concat(old_events_per_page.data.items)

      if !(page_token = old_events_per_page.data.next_page_token)
        break
      end

      old_events_per_page = @client.execute(:api_method => @calendar_api.events.list,
                                           :parameters =>  {'calendarId' => CALENDAR_ID,
                                                            'timeMin' => time_min.iso8601,
                                                            'timeMax' => time_max.iso8601,
                                                            'pageToken' => page_token})
    end

    batch_delete = Google::APIClient::BatchRequest.new

    old_events.each do |event|
      batch_delete.add(:api_method => @calendar_api.events.delete,
                       :parameters => {'calendarId' => CALENDAR_ID,
                                       'eventId' => event.id})
    end

    @old_events_count = old_events.count
    @client.execute(batch_delete) if @old_events_count > 0
  end

  def insert(ical, time_min = @time_min, time_max = @time_max)
    new_events = ical.events

    # 期間チェック
    events_scoped = []
    new_events.each do |event|
      if time_min <= event.dtend && event.dtstart < time_max
        events_scoped << event
      end
    end
    new_events = events_scoped

    # ical -> gcal レイアウト変換
    new_events = new_events.map do |event|

      # 終日イベント
      allday = (event.dtstart.hour == 0 && event.dtstart.min == 0 && event.dtstart.sec == 0 && event.dtend.hour == 0 && event.dtend.min == 0 && event.dtend.sec == 0)

      # タイトル
      if event.categories.class == Array && event.categories.length != 0 && event.categories.flatten.first != ""
        title = "[#{event.categories.flatten.first}] "
      else
        title = ""
      end
      title = title + "#{event.summary}" if event.present?
      title = title + " @ #{event.location}" if event.present?

      # 概要
      description = "開催者: #{event.organizer}"
      description = description + "\ndescription: #{event.description}" if event.description.present?

      e = {
        summary: title,
        description: description,
        location: event.location,
        organizer: event.organizer,
        start: {dateTime: event.dtstart.iso8601},
        end: {dateTime: event.dtend.iso8601},
        url: event.url.to_s
      }

      if allday
        e.update({
          start: {date: Time.local(event.dtstart.year, event.dtstart.month, event.dtstart.day).strftime('%Y-%m-%d')},
          end: {date: Time.local(event.dtend.year, event.dtend.month, event.dtend.day).strftime('%Y-%m-%d')}
        })
      end
      e
    end

    batch_insert = Google::APIClient::BatchRequest.new

    new_events.each do |event|
      batch_insert.add(:api_method => @calendar_api.events.insert,
                       :parameters => {'calendarId' => CALENDAR_ID},
                       :body => JSON.dump(event),
                       :headers => {'Content-Type' => 'application/json'})
    end

    @new_events_count = new_events.count
    @client.execute(batch_insert) if @new_events_count > 0
  end
end

ical = Icalendar.parse(File.read('calendar.ics')).first

gcal = Gcal.new
gcal.set_term(Date.today, TERM_MONTHS)
gcal.delete()
gcal.insert(ical)

puts "Result in deleted events: #{gcal.old_events_count}, inserted events: #{gcal.new_events_count}"
