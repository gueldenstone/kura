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
      accept [:name, :tracking, :usual_amount, :auto_replenish, :stock_count, :stock_level]

      argument :tag_ids, {:array, :uuid}, constraints: [remove_nil_items?: true]

      change Kura.Inventory.Item.Changes.NormalizeStock
      change Kura.Inventory.Item.Changes.SetTags
    end

    update :update do
      primary? true
      accept [:name, :usual_amount, :auto_replenish]
      require_atomic? false

      argument :tag_ids, {:array, :uuid}, constraints: [remove_nil_items?: true]

      change Kura.Inventory.Item.Changes.SetTags
    end

    update :change_count do
      description "Add to or subtract from the count, never going below zero."
      require_atomic? false

      argument :delta, :integer, allow_nil?: false

      change Kura.Inventory.Item.Changes.TouchStockChecked

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
      change Kura.Inventory.Item.Changes.TouchStockChecked
    end

    update :set_level do
      accept []
      require_atomic? false

      argument :level, :atom, allow_nil?: false, constraints: [one_of: [:plenty, :low, :empty]]

      validate attribute_equals(:tracking, :level),
        message: "only level items have a level"

      change set_attribute(:stock_level, arg(:level))
      change Kura.Inventory.Item.Changes.TouchStockChecked
    end

    update :confirm_stock do
      description "Records that the stock was checked and found right, without changing it."
      accept []
      require_atomic? false

      change Kura.Inventory.Item.Changes.TouchStockChecked
    end

    update :mark_empty do
      description "Sets the stock to empty (a count of 0, or the level `:empty`). Items that auto-replenish are also put on the shopping list."
      accept []
      require_atomic? false

      change fn changeset, _context ->
        case Ash.Changeset.get_attribute(changeset, :tracking) do
          :count -> Ash.Changeset.force_change_attribute(changeset, :stock_count, 0)
          :level -> Ash.Changeset.force_change_attribute(changeset, :stock_level, :empty)
        end
      end

      change Kura.Inventory.Item.Changes.TouchStockChecked
      change Kura.Inventory.Item.Changes.PutOnList
    end

    read :search do
      description "All items by name, optionally only those where every word of the query is part of the name or a tag."

      argument :query, :string,
        allow_nil?: false,
        default: "",
        constraints: [allow_empty?: true, trim?: false]

      prepare build(sort: [name: :asc], load: [:tags])
      prepare Kura.Inventory.Item.Preparations.MatchWords
    end

    read :to_check do
      description "All items, the ones whose stock was checked or changed longest ago first."

      prepare build(sort: [stock_checked_at: :asc, name: :asc], load: [:tags])
    end

    read :by_ids do
      description "The items with the given ids, by name. Ids that match no item are ignored."
      argument :ids, {:array, :uuid}, allow_nil?: false

      filter expr(id in ^arg(:ids))

      prepare build(sort: [name: :asc], load: [:tags])
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

    attribute :auto_replenish, :boolean do
      description "Regular stock goes on the shopping list when it runs out; other items only when asked."
      allow_nil? false
      public? true
      default false
    end

    attribute :usual_amount, :integer do
      allow_nil? false
      public? true
      default 1
      constraints min: 1
    end

    attribute :tag_key, :string do
      description "The sorted ids of the item's tags as one string; see `Kura.Inventory.Item.Changes.SetTags`."
      allow_nil? false
      default ""
      constraints allow_empty?: true, trim?: false
    end

    attribute :stock_checked_at, :utc_datetime_usec do
      description "When the stock was last changed or confirmed, which is what the inventory check goes by."
      allow_nil? false
      public? true
      default &DateTime.utc_now/0
    end

    timestamps()
  end

  relationships do
    has_many :shopping_entries, Kura.Inventory.ShoppingEntry

    many_to_many :tags, Kura.Inventory.Tag do
      through Kura.Inventory.ItemTag
      source_attribute_on_join_resource :item_id
      destination_attribute_on_join_resource :tag_id
    end
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
    identity :unique_item, [:name, :tag_key],
      pre_check?: true,
      message: "is already in the inventory with these tags"
  end

  @doc "The string that stands for a set of tag ids in `tag_key`."
  def tag_key(tag_ids), do: tag_ids |> Enum.map(&to_string/1) |> Enum.sort() |> Enum.join(",")

  @doc "The tag names of a loaded item, in alphabetical order."
  def tag_names(%{tags: tags}) do
    tags |> Enum.map(&to_string(&1.name)) |> Enum.sort_by(&String.downcase/1)
  end

  @doc "The tags of a loaded item as one line, in alphabetical order: `ground · Bio`."
  def tag_line(item), do: item |> tag_names() |> Enum.join(" · ")

  @doc "The name and the tags of a loaded item as one piece of text, as printed on a label."
  def label(%{name: name} = item) do
    case tag_line(item) do
      "" -> to_string(name)
      line -> "#{name} #{String.replace(line, " · ", " ")}"
    end
  end
end
