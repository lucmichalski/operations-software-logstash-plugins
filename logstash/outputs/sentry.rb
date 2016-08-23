# from https://github.com/antho31/logstash-output-sentry/blob/master/lib/logstash/outputs/sentry.rb
# (C) 2014 Dave Clark, MIT license

# encoding: utf-8
require 'logstash/outputs/base'
require 'logstash/namespace'
require 'json'

# Sentry is a modern error logging and aggregation platform.
# * https://getsentry.com/
#
# It’s important to note that Sentry should not be thought of as a log stream, but as an aggregator. 
# It fits somewhere in-between a simple metrics solution (such as Graphite) and a full-on log stream aggregator (like Logstash).
#
# Generate and inform your client key (Settings -> Client key)
# The client key has this form  * https://[key]:[secret]@[host]/[project_id] *
#
# More informations : 
# * https://sentry.readthedocs.org/en/latest/


class LogStash::Outputs::Sentry < LogStash::Outputs::Base
 
  config_name 'sentry'
  
  
  # The key of the client key 
  config :key, :validate => :string, :required => true
  
  # The secret  of the client key
  config :secret, :validate => :string, :required => true
  
  # The project id of the client key
  config :project_id, :validate => :string, :required => true
  
  # The Sentry host 
  config :host, :validate => :string, :default => "https://app.getsentry.com", :required => false 
  
  # This sets the message value in Sentry (the title of your event)
  config :msg, :validate => :string, :default => "Message from logstash", :required => false
  
  # This sets the level value in Sentry (the level tag)
  config :level_tag, :validate => :string, :default => "error", :required => false
  
  # Is the protocole https ? By default yes (host is "https://app.getsentry.com") 
  # If you have installed Sentry in your own machine, maybe you do use http, 
  # so you have to disable ssl ( "use_ssl" => false ) 
  config :use_ssl, :validate => :boolean, :default => true, :required => false 
  
  # If set to true automatically map all logstash defined fields to Sentry extra fields.
  # As an example, the logstash event:
  # [source,ruby]
  #    {
  #      "@timestamp":"2013-12-10T14:36:26.151+0000",
  #      "@version": 1,
  #      "message":"log message",
  #      "host": "host.domain.com",
  #      "nested_field": {
  #                        "key": "value"
  #                      }
  #    }
  # Is mapped to this Sentry  event:
  # [source,ruby]
  # extra {
  #      "@timestamp":"2013-12-10T14:36:26.151+0000",
  #      "@version": 1,
  #      "message":"log message",
  #      "host": "host.domain.com",
  #      "nested_field": {
  #                        "key": "value"
  #                      }
  #    }   
  config :fields_to_tags, :validate => :boolean, :default => false, :required => false
 
  public
  def register
    require 'net/https'
    require 'uri'
    
    @url = "#{host}/api/#{project_id}/store/"
    @uri = URI.parse(@url)

    @client = Net::HTTP.new(@uri.host, @uri.port)
    @client.use_ssl = use_ssl
    @client.verify_mode = OpenSSL::SSL::VERIFY_NONE
 
   @logger.debug("Client", :client => @client.inspect)
  end
 
  public
  def receive(event)
    return unless output?(event)
 
    require 'securerandom'
 
    packet = {
      :event_id => SecureRandom.uuid.gsub('-', ''),
      :timestamp => event['@timestamp'],
      :message => event["#{msg}"] || "#{msg}"
   }

    packet[:level] = "#{level_tag}" 
    packet[:platform] = 'logstash'
    packet[:server_name] = event['host']    
    packet[:extra] = event.to_hash   
   
    if fields_to_tags == true 
       packet[:tags] = event.to_hash
    end 

    @logger.debug("Sentry packet", :sentry_packet => packet)
 
    auth_header = "Sentry sentry_version=5," +
      "sentry_client=raven_logstash/1.0," +
      "sentry_timestamp=#{event['@timestamp'].to_i}," +
      "sentry_key=#{@key}," +
      "sentry_secret=#{@secret}"
 
    request = Net::HTTP::Post.new(@uri.path)
 
    begin
      request.body = packet.to_json
      request.add_field('X-Sentry-Auth', auth_header)
 
      response = @client.request(request)
 
      @logger.info("Sentry response", :request => request.inspect, :response => response.inspect)
 
      raise unless response.code == '200'
    rescue Exception => e
      @logger.warn("Unhandled exception", :request => request.inspect, :response => response.inspect, :exception => e.inspect)
    end
  end
end

