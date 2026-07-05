defmodule DncWatchdog.SqliteFixtures do
  @moduledoc false

  @apple_epoch 978_307_200

  def temp_dir!(prefix \\ "dnc_watchdog_test") do
    dir = Path.join(System.tmp_dir!(), "#{prefix}-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    dir
  end

  def apple_nanoseconds(%DateTime{} = dt) do
    (DateTime.to_unix(dt, :second) - @apple_epoch) * 1_000_000_000
  end

  def apple_seconds(%DateTime{} = dt) do
    DateTime.to_unix(dt, :second) - @apple_epoch
  end

  def create_messages_db(path, opts \\ []) do
    incoming_date = Keyword.get(opts, :incoming_date, ~U[2026-05-20 09:14:00Z])
    attributed_only_date = Keyword.get(opts, :attributed_only_date)
    chat_only_date = Keyword.get(opts, :chat_only_date)
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    Exqlite.Sqlite3.execute(conn, "CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT)")
    Exqlite.Sqlite3.execute(conn, "CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, chat_identifier TEXT)")
    Exqlite.Sqlite3.execute(conn, "CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER)")

    Exqlite.Sqlite3.execute(
      conn,
      "CREATE TABLE message (ROWID INTEGER PRIMARY KEY, date INTEGER, text TEXT, attributedBody BLOB, is_from_me INTEGER, handle_id INTEGER)"
    )

    Exqlite.Sqlite3.execute(conn, "INSERT INTO handle (ROWID, id) VALUES (1, '+18001234567')")
    Exqlite.Sqlite3.execute(conn, "INSERT INTO handle (ROWID, id) VALUES (2, '+15550001234')")
    Exqlite.Sqlite3.execute(conn, "INSERT INTO chat (ROWID, chat_identifier) VALUES (1, '+18187432556')")

    ns = apple_nanoseconds(incoming_date)

    Exqlite.Sqlite3.execute(
      conn,
      "INSERT INTO message (ROWID, date, text, is_from_me, handle_id) VALUES (1, #{ns}, 'Limited time offer', 0, 1)"
    )

    Exqlite.Sqlite3.execute(
      conn,
      "INSERT INTO message (ROWID, date, text, is_from_me, handle_id) VALUES (2, #{ns}, 'Hello friend', 1, 2)"
    )

    if attributed_only_date do
      insert_attributed_message(
        conn,
        3,
        apple_nanoseconds(attributed_only_date),
        make_attributed_body("CA Roofing promo from Annie"),
        0,
        1
      )
    end

    if chat_only_date do
      chat_ns = apple_nanoseconds(chat_only_date)

      insert_attributed_message(
        conn,
        4,
        chat_ns,
        make_attributed_body("CA Roofing promo from Annie via chat"),
        0,
        nil
      )

      Exqlite.Sqlite3.execute(
        conn,
        "INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 4)"
      )
    end

    duplicate_join_date = Keyword.get(opts, :duplicate_join_date)

    if duplicate_join_date do
      dup_ns = apple_nanoseconds(duplicate_join_date)

      Exqlite.Sqlite3.execute(
        conn,
        "INSERT INTO chat (ROWID, chat_identifier) VALUES (2, '+18001234567')"
      )

      Exqlite.Sqlite3.execute(
        conn,
        "INSERT INTO message (ROWID, date, text, is_from_me, handle_id) VALUES (5, #{dup_ns}, 'Duplicate join test', 0, 1)"
      )

      Exqlite.Sqlite3.execute(
        conn,
        "INSERT INTO chat_message_join (chat_id, message_id) VALUES (2, 5)"
      )
    end

    Exqlite.Sqlite3.close(conn)
    path
  end

  def make_attributed_body(text) when is_binary(text) do
    text_bytes = :unicode.characters_to_binary(text)
    len = byte_size(text_bytes)

    length_prefix =
      cond do
        len <= 0x7F ->
          <<len>>

        len <= 0xFFFF ->
          <<0x81>> <> <<len::little-unsigned-size(16)>>

        true ->
          <<0x82>> <> <<len::little-unsigned-size(32)>>
      end

    header = <<0x04, 0x0B, "streamtyped", 0x81, 0xE8, 0x03>>
    classes = <<0x84, 0x84, "NSMutableAttributedString", 0>>
    marker = <<0x01, 0x2B>>

    header <> classes <> marker <> length_prefix <> text_bytes <> <<0x86, 0x84>>
  end

  defp insert_attributed_message(conn, rowid, date, blob, is_from_me, handle_id) do
    hex = Base.encode16(blob, case: :lower)
    handle_sql = if is_nil(handle_id), do: "NULL", else: Integer.to_string(handle_id)

    Exqlite.Sqlite3.execute(
      conn,
      """
      INSERT INTO message (ROWID, date, text, attributedBody, is_from_me, handle_id)
      VALUES (#{rowid}, #{date}, NULL, X'#{hex}', #{is_from_me}, #{handle_sql})
      """
    )
  end

  def create_call_history_db(path, opts \\ []) do
    call_date = Keyword.get(opts, :call_date, ~U[2026-05-20 10:00:00Z])
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    Exqlite.Sqlite3.execute(
      conn,
      """
      CREATE TABLE ZCALLRECORD (
        Z_PK INTEGER PRIMARY KEY,
        ZDATE INTEGER,
        ZDURATION REAL,
        ZORIGINATED INTEGER,
        ZADDRESS TEXT,
        ZNAME TEXT
      )
      """
    )

    seconds = apple_seconds(call_date)

    Exqlite.Sqlite3.execute(
      conn,
      """
      INSERT INTO ZCALLRECORD (Z_PK, ZDATE, ZDURATION, ZORIGINATED, ZADDRESS, ZNAME)
      VALUES (1, #{seconds}, 8.0, 0, '+18009998888', 'Robo Warranty Co')
      """
    )

    Exqlite.Sqlite3.close(conn)
    path
  end

  def create_contacts_db(path, phones \\ ["+1 (800) 123-4567"], emails \\ []) do
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    Exqlite.Sqlite3.execute(
      conn,
      """
      CREATE TABLE ZABCDPHONENUMBER (
        Z_PK INTEGER PRIMARY KEY,
        ZFULLNUMBER TEXT,
        ZAREACODE TEXT,
        ZLOCALNUMBER TEXT,
        ZCOUNTRYCODE TEXT
      )
      """
    )

    Exqlite.Sqlite3.execute(
      conn,
      "CREATE TABLE ZABCDEMAILADDRESS (Z_PK INTEGER PRIMARY KEY, ZADDRESS TEXT)"
    )

    Enum.with_index(phones, 1)
    |> Enum.each(fn {phone, idx} ->
      Exqlite.Sqlite3.execute(
        conn,
        "INSERT INTO ZABCDPHONENUMBER (Z_PK, ZFULLNUMBER) VALUES (#{idx}, '#{phone}')"
      )
    end)

    Enum.with_index(emails, 1)
    |> Enum.each(fn {email, idx} ->
      Exqlite.Sqlite3.execute(
        conn,
        "INSERT INTO ZABCDEMAILADDRESS (Z_PK, ZADDRESS) VALUES (#{idx}, '#{email}')"
      )
    end)

    Exqlite.Sqlite3.close(conn)
    path
  end

  def create_split_phone_contacts_db(path, area, local, country \\ "1") do
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    Exqlite.Sqlite3.execute(
      conn,
      """
      CREATE TABLE ZABCDPHONENUMBER (
        Z_PK INTEGER PRIMARY KEY,
        ZFULLNUMBER TEXT,
        ZAREACODE TEXT,
        ZLOCALNUMBER TEXT,
        ZCOUNTRYCODE TEXT
      )
      """
    )

    Exqlite.Sqlite3.execute(
      conn,
      """
      INSERT INTO ZABCDPHONENUMBER (Z_PK, ZFULLNUMBER, ZAREACODE, ZLOCALNUMBER, ZCOUNTRYCODE)
      VALUES (1, NULL, '#{area}', '#{local}', '#{country}')
      """
    )

    Exqlite.Sqlite3.execute(
      conn,
      "CREATE TABLE ZABCDEMAILADDRESS (Z_PK INTEGER PRIMARY KEY, ZADDRESS TEXT)"
    )

    Exqlite.Sqlite3.close(conn)
    path
  end

  def create_me_card_contacts_db(path, attrs \\ %{}) do
    {:ok, conn} = Exqlite.Sqlite3.open(path)

    Exqlite.Sqlite3.execute(
      conn,
      """
      CREATE TABLE ZABCDRECORD (
        Z_PK INTEGER PRIMARY KEY,
        ZME INTEGER,
        ZNAME TEXT,
        ZFIRSTNAME TEXT,
        ZLASTNAME TEXT,
        ZORGANIZATION TEXT
      )
      """
    )

    Exqlite.Sqlite3.execute(
      conn,
      """
      CREATE TABLE ZABCDPOSTALADDRESS (
        Z_PK INTEGER PRIMARY KEY,
        ZOWNER INTEGER,
        ZSTREET TEXT,
        ZCITY TEXT,
        ZSTATE TEXT,
        ZZIPCODE TEXT,
        ZISPRIMARY INTEGER,
        ZORDERINGINDEX INTEGER
      )
      """
    )

    Exqlite.Sqlite3.execute(
      conn,
      """
      CREATE TABLE ZABCDPHONENUMBER (
        Z_PK INTEGER PRIMARY KEY,
        ZOWNER INTEGER,
        ZFULLNUMBER TEXT,
        ZISPRIMARY INTEGER,
        ZORDERINGINDEX INTEGER
      )
      """
    )

    Exqlite.Sqlite3.execute(
      conn,
      """
      CREATE TABLE ZABCDEMAILADDRESS (
        Z_PK INTEGER PRIMARY KEY,
        ZOWNER INTEGER,
        ZADDRESS TEXT,
        ZISPRIMARY INTEGER,
        ZORDERINGINDEX INTEGER
      )
      """
    )

    name = Map.get(attrs, :name, "Mark Example")
    street = Map.get(attrs, :street, "123 Oak St")
    city = Map.get(attrs, :city, "Palo Alto")
    state = Map.get(attrs, :state, "CA")
    zip = Map.get(attrs, :zip, "94301")
    phone = Map.get(attrs, :phone, "+1 (415) 971-9595")
    email = Map.get(attrs, :email, "mark@example.com")

    Exqlite.Sqlite3.execute(
      conn,
      "INSERT INTO ZABCDRECORD (Z_PK, ZME, ZNAME) VALUES (1, 1, '#{name}')"
    )

    Exqlite.Sqlite3.execute(
      conn,
      """
      INSERT INTO ZABCDPOSTALADDRESS (Z_PK, ZOWNER, ZSTREET, ZCITY, ZSTATE, ZZIPCODE, ZISPRIMARY, ZORDERINGINDEX)
      VALUES (1, 1, '#{street}', '#{city}', '#{state}', '#{zip}', 1, 0)
      """
    )

    Exqlite.Sqlite3.execute(
      conn,
      """
      INSERT INTO ZABCDPHONENUMBER (Z_PK, ZOWNER, ZFULLNUMBER, ZISPRIMARY, ZORDERINGINDEX)
      VALUES (1, 1, '#{phone}', 1, 0)
      """
    )

    Exqlite.Sqlite3.execute(
      conn,
      """
      INSERT INTO ZABCDEMAILADDRESS (Z_PK, ZOWNER, ZADDRESS, ZISPRIMARY, ZORDERINGINDEX)
      VALUES (1, 1, '#{email}', 1, 0)
      """
    )

    Exqlite.Sqlite3.close(conn)
    path
  end

  def write_source_db(path, sql) do
    {:ok, conn} = Exqlite.Sqlite3.open(path)
    Exqlite.Sqlite3.execute(conn, sql)
    Exqlite.Sqlite3.close(conn)
    path
  end
end
