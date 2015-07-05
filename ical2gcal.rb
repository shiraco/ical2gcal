# coding: utf-8
require 'google/api_client'
require 'icalendar'
require 'dotenv'

Dotenv.load
SECRET_KEY_PATH=ENV['SECRET_KEY_PATH']
SECRET_KEY_PASSWORD=ENV['SECRET_KEY_PASSWORD']
CALENDAR_ID=ENV['CALENDAR_ID']
SERVICE_ACCOUNT_EMAIL=ENV['SERVICE_ACCOUNT_EMAIL']
APPLICATION_NAME=ENV['APPLICATION_NAME']
MAX_BATCH_SIZE=1000

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

# ical読み込み
ical = Icalendar.parse(File.read('calendar.ics')).first
events = ical.events

# ical -> gcal レイアウト変換
events = events.map do |event|
  {
    summary: event.summary,
    location: event.location,
    description: event.description,
    start: {dateTime: event.dtstart.iso8601},
    end: {dateTime: event.dtend.iso8601},
    url: event.url.to_s
  }
end
puts "events: #{events[0]}"

# カレンダー登録
batch = Google::APIClient::BatchRequest.new

events.each do |event|
  batch.add(:api_method => calendar_api.events.insert,
            :parameters => {'calendarId' => CALENDAR_ID},
            :body => JSON.dump(event),
            :headers => {'Content-Type' => 'application/json'})
end

client.execute(batch)
