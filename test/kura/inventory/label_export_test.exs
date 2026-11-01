defmodule Kura.Inventory.LabelExportTest do
  use ExUnit.Case, async: true

  alias Kura.Inventory.LabelExport

  # Tags are named after themselves, so that their ids are easy to compare.
  defp tag(name, print? \\ true), do: %{id: name, name: name, print_on_labels: print?}

  defp item(name, tags \\ []), do: %{name: name, tags: tags}

  defp csv(items, inventory \\ nil), do: LabelExport.csv(items, inventory || items)

  test "has a Label header and one row per item" do
    assert csv([item("Apples"), item("Walnuts")]) == "Label\r\nApples\r\nWalnuts\r\n"
  end

  test "is just the header without items" do
    assert LabelExport.csv([], []) == "Label\r\n"
  end

  test "quotes names with commas and doubles quotes" do
    items = [item("Salt, coarse"), item(~s(The "good" oil))]

    assert csv(items) == ~s(Label\r\n"Salt, coarse"\r\n"The ""good"" oil"\r\n)
  end

  describe "which tags are printed" do
    test "none for an item whose name is unique" do
      assert csv([item("Cumin", [tag("ground"), tag("Bio")])]) == "Label\r\nCumin\r\n"
    end

    test "those that tell items with the same name apart, not those they all share" do
      hot = item("Paprika", [tag("hot"), tag("ground")])
      sweet = item("Paprika", [tag("sweet"), tag("ground")])

      assert csv([hot, sweet]) == "Label\r\nPaprika hot\r\nPaprika sweet\r\n"
    end

    test "all of them when they differ, in alphabetical order after the name" do
      hot = item("Paprika", [tag("hot"), tag("ground")])
      smoked = item("Paprika", [tag("smoked"), tag("sweet")])

      assert csv([hot, smoked]) ==
               "Label\r\nPaprika ground hot\r\nPaprika smoked sweet\r\n"
    end

    test "never those that are switched off, even when they tell items apart" do
      whole = item("Cumin", [tag("whole", false)])
      ground = item("Cumin", [tag("ground", false)])

      assert csv([whole, ground]) == "Label\r\nCumin\r\nCumin\r\n"
    end

    test "compares with the whole inventory, not just the selected items" do
      hot = item("Paprika", [tag("hot"), tag("ground")])
      sweet = item("Paprika", [tag("sweet"), tag("ground")])
      plain = item("Paprika", [])

      assert csv([hot], [hot, sweet, plain]) == "Label\r\nPaprika ground hot\r\n"
    end

    test "ignores the case of the name when looking for items with the same name" do
      hot = item("Paprika", [tag("hot")])
      sweet = item("paprika", [tag("sweet")])

      assert csv([hot], [hot, sweet]) == "Label\r\nPaprika hot\r\n"
    end

    test "quotes the label when a tag needs it" do
      one = item("Chilli", [tag("Usbekistan, dried")])
      two = item("Chilli", [])

      assert csv([one], [one, two]) == ~s(Label\r\n"Chilli Usbekistan, dried"\r\n)
    end
  end
end
