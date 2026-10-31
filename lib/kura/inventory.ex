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
      define :change_item_count, action: :change_count, args: [:delta]
      define :set_item_count, action: :set_count, args: [:count]
      define :set_item_level, action: :set_level, args: [:level]
      define :mark_item_empty, action: :mark_empty
    end
  end
end
