class HookJob < MutexApplicationJob
  retry_on LockAcquisitionError, wait: 3.seconds, attempts: 3

  queue_as :medium

  def perform(hook, event_name, event_data = {})
    return if hook.disabled?

    case hook.app_id
    when 'slack'
      process_slack_integration(hook, event_name, event_data)
    when 'dialogflow'
      process_dialogflow_integration(hook, event_name, event_data)
    when 'google_translate'
      google_translate_integration(hook, event_name, event_data)
    when 'leadsquared'
      process_leadsquared_integration_with_lock(hook, event_name, event_data)
    when 'glpi'
      process_glpi_integration_with_lock(hook, event_name, event_data)
    when 'krayin'
      process_krayin_integration_with_lock(hook, event_name, event_data)
    end
  rescue StandardError => e
    Rails.logger.error e
  end

  private

  def process_slack_integration(hook, event_name, event_data)
    return unless ['message.created'].include?(event_name)

    message = event_data[:message]
    if message.attachments.blank?
      ::SendOnSlackJob.perform_later(message, hook)
    else
      ::SendOnSlackJob.set(wait: 2.seconds).perform_later(message, hook)
    end
  end

  def process_dialogflow_integration(hook, event_name, event_data)
    return unless ['message.created', 'message.updated'].include?(event_name)

    Integrations::Dialogflow::ProcessorService.new(event_name: event_name, hook: hook, event_data: event_data).perform
  end

  def google_translate_integration(hook, event_name, event_data)
    return unless ['message.created'].include?(event_name)

    message = event_data[:message]
    Integrations::GoogleTranslate::DetectLanguageService.new(hook: hook, message: message).perform
  end

  def process_leadsquared_integration_with_lock(hook, event_name, event_data)
    # Why do we need a mutex here? glad you asked
    # When a new conversation is created. We get a contact created event, immediately followed by
    # a contact updated event, and then a conversation created event.
    # This all happens within milliseconds of each other.
    # Now each of these subsequent event handlers need to have a leadsquared lead created and the contact to have the ID.
    # If the lead data is not present, we try to search the API and create a new lead if it doesn't exist.
    # This gives us a bad race condition that allows the API to create multiple leads for the same contact.
    #
    # This would have not been a problem if the email and phone number were unique identifiers for contacts at LeadSquared
    # But then this is configurable in the LeadSquared settings, and may or may not be unique.
    valid_event_names = ['contact.updated', 'conversation.created', 'conversation.resolved']
    return unless valid_event_names.include?(event_name)
    return unless hook.feature_allowed?

    key = format(::Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: hook.id)
    with_lock(key) do
      process_leadsquared_integration(hook, event_name, event_data)
    end
  end

  def process_leadsquared_integration(hook, event_name, event_data)
    # Process the event with the processor service
    processor = Crm::Leadsquared::ProcessorService.new(hook)

    case event_name
    when 'contact.updated'
      processor.handle_contact(event_data[:contact])
    when 'conversation.created'
      processor.handle_conversation_created(event_data[:conversation])
    when 'conversation.resolved'
      processor.handle_conversation_resolved(event_data[:conversation])
    end
  end

  def process_glpi_integration_with_lock(hook, event_name, event_data)
    # Similar to LeadSquared, GLPI needs mutex protection to prevent race conditions
    # When a new conversation is created, we get:
    # 1. contact.created event
    # 2. contact.updated event (immediately after)
    # 3. conversation.created event
    #
    # Each event handler needs the GLPI User/Contact to exist before creating tickets.
    # Without a mutex, multiple API calls could create duplicate Users/Contacts.
    valid_event_names = ['contact.created', 'contact.updated', 'conversation.created', 'conversation.updated']
    return unless valid_event_names.include?(event_name)
    return unless hook.feature_allowed?

    key = format(::Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: hook.id)
    with_lock(key) do
      process_glpi_integration(hook, event_name, event_data)
    end
  end

  def process_glpi_integration(hook, event_name, event_data)
    # Process the event with the GLPI processor service
    processor = Crm::Glpi::ProcessorService.new(hook)
    processor.process_event(event_name, event_data)
  end

  def process_krayin_integration_with_lock(hook, event_name, event_data)
    # Similar to LeadSquared, we need mutex protection to prevent race conditions
    # when multiple events fire simultaneously (contact.created -> contact.updated -> conversation.created)
    valid_event_names = ['contact.created', 'contact.updated', 'conversation.created', 'conversation.updated', 'message.created']
    return unless valid_event_names.include?(event_name)
    return unless hook.feature_allowed?

    key = format(::Redis::Alfred::CRM_PROCESS_MUTEX, hook_id: hook.id)
    with_lock(key) do
      process_krayin_integration(hook, event_name, event_data)
    end
  end

  def process_krayin_integration(hook, event_name, event_data)
    # Get inbox for the hook
    inbox = hook.inbox
    return unless inbox

    # Process the event with the processor service
    processor = Crm::Krayin::ProcessorService.new(inbox: inbox, event_name: event_name, event_data: event_data)
    processor.perform
  end
end
