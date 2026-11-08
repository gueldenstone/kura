defmodule Kura.Inventory.Location do
  @moduledoc """
  A place in the kitchen where items live: a drawer, a cupboard shelf, the fridge. An item can be
  in several locations; the stock stays per item. Locations say where to look, they are not part
  of an item's identity (unlike tags, ADR 0010). See ADR 0011.
  """
  use Ash.Resource,
    otp_app: :kura,
    domain: Kura.Inventory,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "locations"
    repo Kura.Repo
  end

  actions do
    defaults [:read, :destroy, create: [:name], update: [:name]]

    read :list do
      description "All locations by name, with the number of items that live there."
      prepare build(load: [:item_count])

      # SQLite sorts capital letters first; the list is ordered ignoring case.
      prepare fn query, _context ->
        Ash.Query.after_action(query, fn _query, locations ->
          {:ok, Enum.sort_by(locations, &String.downcase(to_string(&1.name)))}
        end)
      end
    end
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
    publish_all :update, "changed"
    publish_all :destroy, "changed"
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :ci_string do
      allow_nil? false
      public? true
      constraints min_length: 1, trim?: true
    end

    timestamps()
  end

  relationships do
    many_to_many :items, Kura.Inventory.Item do
      through Kura.Inventory.ItemLocation
      source_attribute_on_join_resource :location_id
      destination_attribute_on_join_resource :item_id
    end
  end

  aggregates do
    count :item_count, :items

    count :stock_item_count, :items do
      description "The items in this place that have stock, which is what the inventory check walks."
      filter expr(tracking != :none)
    end
  end

  identities do
    identity :unique_name, [:name], pre_check?: true
  end
end
