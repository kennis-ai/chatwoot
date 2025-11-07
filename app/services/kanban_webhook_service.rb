class KanbanWebhookService
  def initialize(account)
    @account = account
  end

  def notify_item_created(item)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.created')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.created')
    KanbanWebhookJob.perform_later(webhook_url, payload, 'item_created')
  end

  def notify_item_updated(item, changes = {})
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.updated')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.updated', changes: changes)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'item_updated')
  end

  def notify_item_deleted(item)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.deleted')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.deleted')
    KanbanWebhookJob.perform_later(webhook_url, payload, 'item_deleted')
  end

  def notify_stage_change(item, from_stage, to_stage)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.item.stage_changed')

    webhook_url = get_webhook_url
    payload = build_payload(item, 'kanban.item.stage_changed',
                            from_stage: from_stage, to_stage: to_stage)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'stage_changed')
  end

  def notify_item_reordered(items, changes)
    return unless webhook_enabled? && webhook_event_enabled?('kanban.items.reordered')

    webhook_url = get_webhook_url
    payload = build_payload(items, 'kanban.items.reordered', changes: changes)
    KanbanWebhookJob.perform_later(webhook_url, payload, 'items_reordered')
  end

  private

  def get_webhook_url
    # Buscar URL do webhook das configurações da conta
    @account.kanban_config&.webhook_url
  end

  def webhook_enabled?
    @account.kanban_config&.webhook_enabled? || false
  end

  def webhook_event_enabled?(event)
    return false unless webhook_enabled?
    return false unless @account.kanban_config&.webhook_events&.include?(event)

    true
  end

  def build_payload(item, event, additional_data = {})
    base_payload = {
      event: event,
      data: {
        item: format_item_data(item),
        timestamp: Time.current,
        account_id: @account.id,
        account_name: @account.name
      }
    }

    # Adicionar dados específicos do evento
    base_payload[:data].merge!(additional_data) if additional_data.present?

    base_payload
  end

  def format_item_data(item)
    if item.is_a?(Array)
      item.map { |i| format_single_item(i) }
    else
      format_single_item(item)
    end
  end

  def format_single_item(item)
    {
      id: item.id,
      account_id: item.account_id,
      conversation_display_id: item.conversation_display_id,
      funnel_id: item.funnel_id,
      funnel_stage: item.funnel_stage,
      stage_entered_at: item.stage_entered_at,
      position: item.position,
      custom_attributes: item.custom_attributes || {},
      item_details: item.item_details || {},
      timer_started_at: item.timer_started_at,
      timer_duration: item.timer_duration,
      assigned_agents: item.assigned_agents || [],
      checklist: item.checklist || [],
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end
end
