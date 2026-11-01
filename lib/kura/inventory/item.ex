defmodule Kura.Inventory.Item do
  @moduledoc """
  A kitchen item in the permanent catalogue. Items are never removed when they run out;
  they are just empty. Each item tracks its stock either as a `:count` or as a `:level`.
  """
  use Ash.Resource,
    otp_app: :kura,
    domain: Kura.Inventory,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  sqlite do
    table "items"
    repo Kura.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :tracking, :usual_amount, :stock_count, :stock_level]

      change Kura.Inventory.Item.Changes.NormalizeStock
    end

    update :update do
      primary? true
      accept [:name, :usual_amount]
    end

    update :change_count do
      description "Add to or subtract from the count, never going below zero."
      require_atomic? false

      argument :delta, :integer, allow_nil?: false

      validate attribute_equals(:tracking, :count),
        message: "only count items have a count"

      change fn changeset, _context ->
        current = Ash.Changeset.get_attribute(changeset, :stock_count) || 0
        delta = Ash.Changeset.get_argument(changeset, :delta)

        Ash.Changeset.force_change_attribute(changeset, :stock_count, max(current + delta, 0))
      end
    end

    update :set_count do
      accept []
      require_atomic? false

      argument :count, :integer, allow_nil?: false, constraints: [min: 0]

      validate attribute_equals(:tracking, :count),
        message: "only count items have a count"

      change set_attribute(:stock_count, arg(:count))
    end

    update :set_level do
      accept []
      require_atomic? false

      argument :level, :atom, allow_nil?: false, constraints: [one_of: [:plenty, :low, :empty]]

      validate attribute_equals(:tracking, :level),
        message: "only level items have a level"

      change set_attribute(:stock_level, arg(:level))
    end

    update :mark_empty do
      description "Sets the stock to empty (a count of 0, or the level `:empty`) and puts the item on the shopping list."
      accept []
      require_atomic? false

      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :tracking) do
          :count -> Ash.Changeset.force_change_attribute(changeset, :stock_count, 0)
          :level -> Ash.Changeset.force_change_attribute(changeset, :stock_level, :empty)
        end
      end

      change Kura.Inventory.Item.Changes.PutOnList
    end

    read :search do
      description "All items by name, optionally only those whose name contains the query."

      argument :query, :string,
        allow_nil?: false,
        default: "",
        constraints: [allow_empty?: true, trim?: false]

      filter expr(contains(name, ^arg(:query)))

      prepare build(sort: [name: :asc])
    end

    read :by_ids do
      description "The items with the given ids, by name. Ids that match no item are ignored."
      argument :ids, {:array, :uuid}, allow_nil?: false

      filter expr(id in ^arg(:ids))

      prepare build(sort: [name: :asc])
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

    # Every change goes to one topic; the LiveViews simply reload when anything happens.
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

    attribute :tracking, :atom do
      allow_nil? false
      public? true
      writable? true
      constraints one_of: [:count, :level]
    end

    attribute :stock_count, :integer do
      public? true
      constraints min: 0
    end

    attribute :stock_level, :atom do
      public? true
      constraints one_of: [:plenty, :low, :empty]
    end

    attribute :usual_amount, :integer do
      allow_nil? false
      public? true
      default 1
      constraints min: 1
    end

    timestamps()
  end

  relationships do
    has_many :shopping_entries, Kura.Inventory.ShoppingEntry
  end

  calculations do
    calculate :on_list?, :boolean, expr(exists(shopping_entries, is_nil(checked_at)))

    calculate :empty?,
              :boolean,
              expr(
                (tracking == :count and stock_count == 0) or
                  (tracking == :level and stock_level == :empty)
              )
  end

  identities do
    identity :unique_name, [:name], pre_check?: true
  end
end
