#
# Author:: Dell Cloud Manager OSS
# Copyright:: Dell, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "chef"
require "chef/handler"
require 'net/http'
require "timeout"

class Chef::Handler::Slack < Chef::Handler
  attr_reader :webhooks, :username, :config, :timeout, :icon_emoji, :fail_only, :message_detail_level, :cookbook_detail_level

  def initialize(config = {})
    Chef::Log.debug('Initializing Chef::Handler::Slack')
    @config = config
    @timeout = @config[:timeout]
    @icon_emoji = @config[:icon_emoji]
    @icon_url = @config[:icon_url]
    @username = @config[:username]
    @webhooks = @config[:webhooks]
    @fail_only = @config[:fail_only]
    @message_detail_level = @config[:message_detail_level]
    @cookbook_detail_level = @config[:cookbook_detail_level]
  end

  def report
    @webhooks['name'].each do |val|
      Chef::Log.debug("Sending handler report to webhook #{val}")
      webhook = node['chef_client']['handler']['slack']['webhooks'][val]
      Timeout.timeout(@timeout) do
        sending_to_slack = false

        if run_status.success?
          unless fail_only(webhook)
            slack_message(" :white_check_mark: #{message(webhook)}", webhook['url'])
            sending_to_slack = true
          end
        else
          sending_to_slack = true
          slack_message(" :skull: #{message(webhook)}", webhook['url'], run_status.exception)
        end
        Chef::Log.info("Sending report to Slack webhook #{webhook['url']}") if sending_to_slack
      end
    end
  rescue Exception => e
    Chef::Log.warn("Failed to send message to Slack: #{e.message}")
  end

  private

  def fail_only(webhook)
    return webhook['fail_only'] unless webhook['fail_only'].nil?
    @fail_only
  end

  def message(context)
    "Chef client run #{run_status_human_readable} on #{run_status.node.name}#{run_status_cookbook_detail(context['cookbook_detail_level'])}#{run_status_message_detail(context['message_detail_level'])}"
  end

  def run_status_message_detail(message_detail_level)
    message_detail_level ||= @message_detail_level
    case message_detail_level
    when "elapsed"
      " (#{run_status.elapsed_time} seconds). #{updated_resources.count} resources updated" unless updated_resources.nil?
    when "resources"
      " (#{run_status.elapsed_time} seconds). #{updated_resources.count} resources updated \n #{updated_resources.join(', ')}" unless updated_resources.nil?
    end
  end

  def slack_message(message, webhook, text_attachment = nil)
    Chef::Log.debug("Sending slack message #{message} to webhook #{webhook} #{text_attachment ? 'with' : 'without'} a text attachment")
    uri = URI.parse(webhook)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    req = Net::HTTP::Post.new(uri.path, 'Content-Type' => 'application/json')
    req.body = request_body(message, text_attachment)
    http.request(req)
  end

  def request_body(message, text_attachment)
    body = {}
    body[:username] = @username unless @username.nil?
    body[:text] = message
    # icon_url takes precedence over icon_emoji
    if @icon_url
      body[:icon_url] = @icon_url
    elsif @icon_emoji
      body[:icon_emoji] = @icon_emoji
    end
    body[:attachments] = [{ text: text_attachment }] unless text_attachment.nil?
    body.to_json
  end

  def run_status_human_readable
    run_status.success? ? "succeeded" : "failed"
  end

  def run_status_cookbook_detail(cookbook_detail_level)
    cookbook_detail_level ||= @cookbook_detail_level
    case cookbook_detail_level
    when "all"
      cookbooks = Chef.run_context.cookbook_collection
      " using cookbooks #{cookbooks.values.map { |x| x.name.to_s + ' ' + x.version }}"
    end
  end
end
