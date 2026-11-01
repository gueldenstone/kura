defmodule Kura.Inventory.ItemLocation do
  @moduledoc "Joins an item to one of its locations."
  use Ash.Resource,
    otp_app: :kura,
    domain: Kura.Inventory,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "item_locations"
    repo Kura.Repo

    references do
      reference :item, on_delete: :delete
      reference :location, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy, create: [:item_id, :location_id]]
  end

  policies do
    policy always() do
      authorize_if actor_present()
    end
  end

  pub_sub do
    module KuraWeb.Endpoint
    prefix "kitchen"

    publish_all :create, "changed"
    publish_all :destroy, "changed"
  end

  relationships do
    belongs_to :item, Kura.Inventory.Item, primary_key?: true, allow_nil?: false
    belongs_to :location, Kura.Inventory.Location, primary_key?: true, allow_nil?: false
  end
end
