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
MAX_BATCH_SIZE = 1000
TERRA_TERM = 3

# Initialize the API
client = Google::APIClient.new(:application_name => APPLICATION_NAME)

# 認証
signing_key = Google::APIClient::KeyUtils.load_from_pkcs12(SECRET_KEY_PATH, SECRET_KEY_PASSWORD)
client.authorization = Signet::OAuth2::Client.new(
  :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
  :audience => 'https://accounts.google.com/o/oauth2/token',
  :scope => 'https://www.googleapis.com/auth/calendar',  #
  :issuer => SERVICE_ACCOUNT_EMAIL,
  :signing_key => signing_key)
client.authorization.fetch_access_token!

# calendar_api 取得
calendar_api = client.discovered_api('calendar', 'v3')

# カレンダー削除
today = Date.today
s = Date.new(today.year, today.month, 1)
s = (s << 5)
e = (s >> TERRA_TERM) - 1

time_min = Time.local(s.year, s.month, s.day, 0, 0, 0).iso8601
time_max = Time.local(e.year, e.month, e.day, 23, 59, 59).iso8601

old_events = client.execute(:api_method => calendar_api.events.list,
                            :parameters =>  {'calendarId' => CALENDAR_ID,
                                             'timeMin' => time_min,
                                             'timeMax' => time_max})

while true
  old_events.data.items.each do |event|
    client.execute(:api_method => calendar_api.events.delete,
                   :parameters => {'calendarId' => CALENDAR_ID,
                                   'eventId' => event["id"]})
  end
  if !(page_token = old_events.data.next_page_token)
    break
  end
  old_events = client.execute(:api_method => calendar_api.events.list,
                              :parameters =>  {'calendarId' => CALENDAR_ID,
                                               'timeMin' => time_min,
                                               'timeMax' => time_max,
                                               'pageToken' => page_token})
end

# ical読み込み
ical = Icalendar.parse(File.read('calendar.ics')).first
new_events = ical.events

# ical -> gcal レイアウト変換
new_events = new_events.map do |event|
  {
    summary: event.summary,
    location: event.location,
    description: event.description,
    start: {dateTime: event.dtstart.iso8601},
    end: {dateTime: event.dtend.iso8601},
    url: event.url.to_s
  }
end
puts "events: #{new_events[0]}"

# カレンダー登録
batch = Google::APIClient::BatchRequest.new

new_events.each do |event|
  batch.add(:api_method => calendar_api.events.insert,
            :parameters => {'calendarId' => CALENDAR_ID},
            :body => JSON.dump(event),
            :headers => {'Content-Type' => 'application/json'})
end

client.execute(batch)
