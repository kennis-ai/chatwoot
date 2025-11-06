# frozen_string_literal: true

class Crm::Krayin::Mappers::ConversationMapper
  def self.map_to_activity(conversation, person_id, settings)
    new(conversation).map_to_activity(person_id, settings)
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def map_to_activity(person_id, settings)
    {
      type: determine_activity_type,
      title: activity_title,
      comment: build_activity_comment,
      person_id: person_id,
      is_done: conversation_resolved?
    }.compact
  end

  private

  attr_reader :conversation

  def determine_activity_type
    # Detect activity type based on inbox channel
    inbox_type = @conversation.inbox&.channel&.class&.name

    case inbox_type
    when 'Channel::Email'
      'email'
    when 'Channel::TwilioSms', 'Channel::Sms'
      'call' # SMS conversations as call type
    when 'Channel::Whatsapp'
      'call' # WhatsApp conversations as call type
    when 'Channel::WebWidget', 'Channel::Api'
      'note' # Web chat as note
    else
      'note' # Default
    end
  end

  def activity_title
    "Conversation ##{@conversation.display_id}"
  end

  def build_activity_comment
    parts = []

    parts << "**Conversation Details**"
    parts << "ID: #{@conversation.display_id}"
    parts << "Status: #{@conversation.status.humanize}"
    parts << "Inbox: #{@conversation.inbox&.name}"
    parts << "Assignee: #{@conversation.assignee&.name || 'Unassigned'}"
    parts << "Priority: #{@conversation.priority || 'None'}"
    parts << ""

    # Add labels if present
    if @conversation.labels.any?
      parts << "Labels: #{@conversation.labels.map(&:title).join(', ')}"
      parts << ""
    end

    # Add custom attributes if present
    if @conversation.custom_attributes.present?
      parts << "**Custom Attributes**"
      @conversation.custom_attributes.each do |key, value|
        parts << "#{key.humanize}: #{value}"
      end
      parts << ""
    end

    # Add conversation URL
    parts << "**View Conversation**"
    parts << conversation_url
    parts << ""

    # Add message summary
    parts << "**Recent Messages**"
    parts << message_summary
    parts << ""

    # Add source info
    parts << "Source: #{brand_name}"

    parts.join("\n")
  end

  def conversation_resolved?
    @conversation.status == 'resolved'
  end

  def message_summary
    messages = @conversation.messages.order(created_at: :desc).limit(5)

    return "No messages yet" if messages.empty?

    messages.reverse.map do |message|
      sender = message.sender&.name || 'System'
      timestamp = message.created_at.strftime('%Y-%m-%d %H:%M')
      content = truncate_content(message.content)

      "#{timestamp} - #{sender}: #{content}"
    end.join("\n")
  end

  def truncate_content(content)
    return '' if content.blank?

    # Strip HTML tags
    plain_content = ActionView::Base.full_sanitizer.sanitize(content)

    # Truncate to 150 characters
    plain_content.length > 150 ? "#{plain_content[0..147]}..." : plain_content
  end

  def conversation_url
    account = @conversation.account
    frontend_url = ENV.fetch('FRONTEND_URL', '')

    "#{frontend_url}/app/accounts/#{account.id}/conversations/#{@conversation.display_id}"
  end

  def brand_name
    ::GlobalConfig.get('BRAND_NAME')['BRAND_NAME'] || 'Chatwoot'
  end
end
