defmodule Kura.Inventory.LabelExportTest do
  use ExUnit.Case, async: true

  alias Kura.Inventory.LabelExport

  defp csv(names), do: LabelExport.csv(Enum.map(names, &%{name: &1, tags: []}))

  test "has a Label header and one row per item" do
    assert csv(["Apples", "Walnuts"]) == "Label\r\nApples\r\nWalnuts\r\n"
  end

  test "is just the header without items" do
    assert csv([]) == "Label\r\n"
  end

  test "quotes names with commas and doubles quotes" do
    assert csv(["Salt, coarse", ~s(The "good" oil)]) ==
             ~s(Label\r\n"Salt, coarse"\r\n"The ""good"" oil"\r\n)
  end
end
