class AddActivitiesToKanbanItems < ActiveRecord::Migration[7.1]
  def up
    # Skip if kanban_items table doesn't exist (Kanban integration not yet installed)
    return unless table_exists?(:kanban_items)

    # Skip if activities column already exists
    return if column_exists?(:kanban_items, :activities)

    # Adicionar o novo campo activities
    add_column :kanban_items, :activities, :jsonb, default: []

    # Migrar dados existentes do item_details['activities'] para o novo campo activities
    if defined?(KanbanItem)
      KanbanItem.reset_column_information

      KanbanItem.find_each do |kanban_item|
        if kanban_item.item_details.is_a?(Hash) && kanban_item.item_details['activities'].present?
          # Mover o activities para o novo campo
          kanban_item.update_column(:activities, kanban_item.item_details['activities'])

          # Remover o activities do item_details
          item_details_without_activities = kanban_item.item_details.except('activities')
          kanban_item.update_column(:item_details, item_details_without_activities)
        end
      end
    end

    # Adicionar índice GIN para o novo campo activities
    add_index :kanban_items, :activities, using: :gin unless index_exists?(:kanban_items, :activities)
  end

  def down
    # Skip if kanban_items table doesn't exist
    return unless table_exists?(:kanban_items)

    # Skip if activities column doesn't exist
    return unless column_exists?(:kanban_items, :activities)

    # Migrar dados de volta para item_details
    if defined?(KanbanItem)
      KanbanItem.reset_column_information

      KanbanItem.find_each do |kanban_item|
        if kanban_item.activities.present?
          # Mover o activities de volta para item_details
          item_details_with_activities = kanban_item.item_details.merge('activities' => kanban_item.activities)
          kanban_item.update_column(:item_details, item_details_with_activities)
        end
      end
    end

    # Remover o índice
    remove_index :kanban_items, :activities if index_exists?(:kanban_items, :activities)

    # Remover o campo activities
    remove_column :kanban_items, :activities
  end
end
