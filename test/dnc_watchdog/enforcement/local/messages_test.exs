defmodule DncWatchdog.Enforcement.Local.MessagesTest do
  use ExUnit.Case, async: true

  alias DncWatchdog.Enforcement.Local.Messages
  alias DncWatchdog.SqliteFixtures

  setup do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)
    path = Path.join(dir, "chat.db")
    SqliteFixtures.create_messages_db(path)
    %{path: path}
  end

  test "read/2 returns incoming and outgoing sms rows", %{path: path} do
    assert {:ok, rows} = Messages.read(path, limit: 10, my_phone: "5550001234")
    assert length(rows) == 2

    incoming = Enum.find(rows, &(&1.direction == "incoming"))
    outgoing = Enum.find(rows, &(&1.direction == "outgoing"))

    assert incoming.channel == "sms"
    assert incoming.from_number == "8001234567"
    assert incoming.body =~ "Limited time"

    assert outgoing.direction == "outgoing"
    assert outgoing.to_number == "5550001234"
  end

  test "read/2 works when my_phone is nil", %{path: path} do
    assert {:ok, rows} = Messages.read(path, limit: 10, my_phone: nil)
    assert length(rows) == 2
    assert Enum.all?(rows, &is_binary(&1.from_number))
  end

  test "read/2 returns error for missing file" do
    assert {:error, message} = Messages.read("/no/such/chat.db")
    assert message =~ "not found"
  end

  test "read/2 returns error for unexpected schema", %{path: path} do
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    Exqlite.Sqlite3.execute(conn, "DROP TABLE message")
    Exqlite.Sqlite3.close(conn)

    assert {:error, message} = Messages.read(path)
    assert message =~ "Unexpected Messages schema"
  end

  test "read/2 decodes attributedBody when text column is empty" do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    path =
      SqliteFixtures.create_messages_db(Path.join(dir, "chat.db"),
        attributed_only_date: ~U[2026-06-09 15:30:00Z]
      )

    assert {:ok, rows} = Messages.read(path, limit: 10, my_phone: "5550001234")
    assert length(rows) == 3

    attributed =
      Enum.find(rows, fn row ->
        row.from_number == "8001234567" and String.contains?(row.body, "CA Roofing")
      end)

    assert attributed.direction == "incoming"
    assert attributed.channel == "sms"
  end

  test "read/2 resolves sender from chat.chat_identifier when handle_id is null" do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    path =
      SqliteFixtures.create_messages_db(Path.join(dir, "chat.db"),
        chat_only_date: ~U[2026-06-09 15:30:00Z]
      )

    assert {:ok, rows} = Messages.read(path, limit: 10, my_phone: "5550001234")

    attributed =
      Enum.find(rows, fn row ->
        row.from_number == "8187432556" and String.contains?(row.body, "via chat")
      end)

    assert attributed.direction == "incoming"
  end

  test "search/3 finds rows by phone fragment" do
    dir = SqliteFixtures.temp_dir!()
    on_exit(fn -> File.rm_rf(dir) end)

    path =
      SqliteFixtures.create_messages_db(Path.join(dir, "chat.db"),
        chat_only_date: ~U[2026-06-09 15:30:00Z]
      )

    assert {:ok, hits} = Messages.search(path, "8187432556")
    assert length(hits) == 1
    assert hd(hits).decoded_body =~ "via chat"
  end
end
