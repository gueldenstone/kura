defmodule Kura.Inventory.Tag do
  @moduledoc """
  A detail an item can carry, such as "ground", "whole" or "Bio". Tags are shared by all items and
  together with the name they tell items apart: "Cumin" tagged "ground" and "Cumin" tagged "whole"
  are two items. See ADR 0010.
  """
  use Ash.Resource,
    otp_app: :kura,
    domain: Kura.Inventory,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "tags"
    repo Kura.Repo
  end

  actions do
    defaults [:read]

    read :list do
      description "All tags by name, with the number of items that carry each."
      prepare build(sort: [name: :asc], load: [:item_count])

      # SQLite sorts capital letters first; the list is ordered ignoring case.
      prepare fn query, _context ->
        Ash.Query.after_action(query, fn _query, tags ->
          {:ok, Enum.sort_by(tags, &String.downcase(to_string(&1.name)))}
        end)
      end
    end

    create :create do
      primary? true
      accept [:name]
    end

    update :update do
      primary? true
      accept [:name]
    end

    destroy :destroy do
      description "Deletes the tag and takes it off its items, unless that would make two items identical."
      primary? true
      require_atomic? false

      change Kura.Inventory.Tag.Changes.RemoveFromItems
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
      through Kura.Inventory.ItemTag
      source_attribute_on_join_resource :tag_id
      destination_attribute_on_join_resource :item_id
    end
  end

  aggregates do
    count :item_count, :items
  end

  identities do
    identity :unique_name, [:name], pre_check?: true
  end
end
