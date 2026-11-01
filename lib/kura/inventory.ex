defmodule Kura.Inventory do
  use Ash.Domain, otp_app: :kura, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Kura.Inventory.Item do
      define :create_item, action: :create
      define :update_item, action: :update
      define :delete_item, action: :destroy
      define :get_item, action: :read, get_by: :id
      define :search_items, action: :search, args: [:query]
      define :list_items_by_ids, action: :by_ids, args: [:ids]
      define :change_item_count, action: :change_count, args: [:delta]
      define :set_item_count, action: :set_count, args: [:count]
      define :set_item_level, action: :set_level, args: [:level]
      define :mark_item_empty, action: :mark_empty
    end

    resource Kura.Inventory.ShoppingEntry do
      define :add_entry, action: :add
      define :get_entry, action: :read, get_by: :id
      define :change_entry_quantity, action: :change_quantity, args: [:delta]
      define :check_off_entry, action: :check_off
      define :uncheck_entry, action: :uncheck
      define :remove_entry, action: :destroy
      define :list_open_entries, action: :open
      define :list_checked_entries, action: :checked
    end
  end
end
