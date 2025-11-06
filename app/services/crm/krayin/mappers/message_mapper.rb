# frozen_string_literal: true

class Crm::Krayin::Mappers::MessageMapper
  def self.map_to_activity(message, person_id, settings)
    new(message).map_to_activity(person_id, settings)
  end

  def initialize(message)
    @message = message
  end

  def map_to_activity(person_id, settings)
    {
      type: activity_type,
      title: activity_title,
      comment: build_activity_comment,
      person_id: person_id,
      is_done: true
    }.compact
  end

  private

  attr_reader :message

  def activity_type
    # Detect activity type based on inbox channel
    inbox_type = @message.inbox&.channel&.class&.name

    case inbox_type
    when 'Channel::Email'
      'email'
    when 'Channel::TwilioSms', 'Channel::Sms'
      'call' # SMS treated as call type in Krayin
    when 'Channel::Whatsapp'
      'call' # WhatsApp treated as call type
    when 'Channel::WebWidget', 'Channel::Api'
      detect_from_message_type # Web chat or API
    else
      detect_from_message_type # Fallback to message type detection
    end
  end

  def detect_from_message_type
    # Fallback detection based on message type
    case @message.message_type
    when 'outgoing'
      'email' # Outgoing messages treated as email activities
    when 'incoming'
      'note'  # Incoming messages treated as notes
    else
      'note'  # Default to note for other types
    end
  end

  def activity_title
    conversation_id = @message.conversation&.display_id || 'Unknown'
    sender_name = @message.sender&.name || 'System'

    "Message from #{sender_name} - Conversation ##{conversation_id}"
  end

  def build_activity_comment
    parts = []

    parts << "**Message Details**"
    parts << "From: #{sender_info}"
    parts << "Type: #{@message.message_type.humanize}"
    parts << "Timestamp: #{@message.created_at.strftime('%Y-%m-%d %H:%M:%S')}"
    parts << ""

    # Add message content
    parts << "**Message Content**"
    parts << format_message_content
    parts << ""

    # Add attachments if present
    if @message.attachments.any?
      parts << "**Attachments**"
      @message.attachments.each do |attachment|
        parts << "- #{attachment.file_type}: #{attachment.file.filename} (#{format_file_size(attachment.file_size)})"
      end
      parts << ""
    end

    # Add conversation context
    if @message.conversation.present?
      parts << "**Conversation Context**"
      parts << "Conversation ID: #{@message.conversation.display_id}"
      parts << "Status: #{@message.conversation.status.humanize}"
      parts << "Inbox: #{@message.conversation.inbox&.name}"
      parts << ""
    end

    # Add source info
    parts << "Source: #{brand_name}"

    parts.join("\n")
  end

  def sender_info
    return 'System' unless @message.sender.present?

    sender = @message.sender
    case sender
    when Contact
      sender.email.presence || sender.phone_number.presence || sender.name
    when User
      "#{sender.name} (Agent)"
    else
      sender.name
    end
  end

  def format_message_content
    return '[No content]' if @message.content.blank?

    # Strip HTML tags for plain text
    plain_content = ActionView::Base.full_sanitizer.sanitize(@message.content)

    # Preserve line breaks
    plain_content.strip
  end

  def format_file_size(size)
    return '0 B' if size.nil? || size.zero?

    units = ['B', 'KB', 'MB', 'GB']
    exp = (Math.log(size) / Math.log(1024)).to_i
    exp = [exp, units.length - 1].min

    "%.2f %s" % [size.to_f / (1024**exp), units[exp]]
  end

  def brand_name
    ::GlobalConfig.get('BRAND_NAME')['BRAND_NAME'] || 'Chatwoot'
  end
end
