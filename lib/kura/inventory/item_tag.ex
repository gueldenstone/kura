defmodule Kura.Inventory.ItemTag do
  @moduledoc "Joins an item to one of its tags."
  use Ash.Resource,
    otp_app: :kura,
    domain: Kura.Inventory,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  sqlite do
    table "item_tags"
    repo Kura.Repo

    references do
      reference :item, on_delete: :delete
      reference :tag, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: [:item_id, :tag_id]]
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  relationships do
    belongs_to :item, Kura.Inventory.Item, primary_key?: true, allow_nil?: false
    belongs_to :tag, Kura.Inventory.Tag, primary_key?: true, allow_nil?: false
  end
end
