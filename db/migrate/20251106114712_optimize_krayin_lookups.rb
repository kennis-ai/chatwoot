# frozen_string_literal: true

class OptimizeKrayinLookups < ActiveRecord::Migration[7.0]
  def change
    # Add partial index for Krayin external IDs
    # This significantly speeds up lookups for contacts synced with Krayin
    add_index :contact_inboxes, :source_id,
              where: "source_id LIKE 'krayin:%'",
              name: 'index_contact_inboxes_on_krayin_source_id'

    # Add index on inbox_id for contact_inboxes to speed up joins
    # This helps when querying contacts for a specific inbox
    add_index :contact_inboxes, [:inbox_id, :source_id],
              where: "source_id LIKE 'krayin:%'",
              name: 'index_contact_inboxes_on_inbox_and_krayin_source'
  end
end
