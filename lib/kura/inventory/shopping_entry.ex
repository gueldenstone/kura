defmodule Kura.Inventory.ShoppingEntry do
  @moduledoc """
  An item on the shopping list, with the quantity to buy. An entry is *open* until it is checked
  off, which restocks the item and moves the entry to "in the cart". Hiding the checked entries
  deletes them. An item has at most one open entry at a time.
  """
  use Ash.Resource,
    otp_app: :kura,
    domain: Kura.Inventory,
    data_layer: AshSqlite.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  alias Kura.Inventory.ShoppingEntry.{Changes, Validations}

  sqlite do
    table "shopping_entries"
    repo Kura.Repo

    references do
      reference :item, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    read :open do
      description "Entries still to buy, by item name."
      filter expr(is_nil(checked_at))
      prepare build(sort: [item_name: :asc], load: [item: [:tags]])
    end

    read :checked do
      description "Entries in the cart, the most recently checked first."
      filter expr(not is_nil(checked_at))
      prepare build(sort: [checked_at: :desc], load: [item: [:tags]])
    end

    create :add do
      description "Puts an item on the list; the quantity defaults to the item's usual amount."
      primary? true
      accept [:item_id, :quantity]

      change Changes.DefaultQuantity
      validate Validations.NotOnList
    end

    update :change_quantity do
      accept []
      require_atomic? false

      argument :delta, :integer, allow_nil?: false

      validate fn changeset, _context -> open_only(changeset) end

      change fn changeset, _context ->
        delta = Ash.Changeset.get_argument(changeset, :delta)
        quantity = Ash.Changeset.get_attribute(changeset, :quantity)

        Ash.Changeset.force_change_attribute(changeset, :quantity, quantity + delta)
      end
    end

    update :check_off do
      description "Moves the entry to the cart and restocks the item."
      accept []
      require_atomic? false

      validate fn changeset, _context -> open_only(changeset) end

      change Changes.CheckOff
    end

    update :uncheck do
      description "Takes the entry out of the cart and reverses the restock."
      accept []
      require_atomic? false

      validate fn changeset, _context ->
        if changeset.data.checked_at,
          do: :ok,
          else: {:error, field: :checked_at, message: "is not checked off"}
      end

      change Changes.Uncheck
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

    attribute :quantity, :integer do
      allow_nil? false
      public? true
      constraints min: 1
    end

    attribute :checked_at, :utc_datetime do
      description "Set when the entry is checked off, i.e. it is in the cart."
      public? true
    end

    attribute :previous_level, :atom do
      description "A level item's level before check-off, so unchecking can restore it."
      constraints one_of: [:plenty, :low, :empty]
    end

    timestamps()
  end

  relationships do
    belongs_to :item, Kura.Inventory.Item do
      allow_nil? false
      public? true
    end
  end

  calculations do
    calculate :item_name, :ci_string, expr(item.name)
  end

  defp open_only(changeset) do
    if changeset.data.checked_at,
      do: {:error, field: :checked_at, message: "is already checked off"},
      else: :ok
  end
end
