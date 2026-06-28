defmodule DncWatchdog.Enforcement.DedupeTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.Communication
  alias DncWatchdog.Enforcement.Dedupe
  alias DncWatchdog.Repo

  import DncWatchdog.EnforcementFixtures

  defp insert_duplicate_communication!(overrides \\ %{}) do
    attrs = communication_attrs(overrides)

    %Communication{}
    |> Communication.changeset(attrs)
    |> Repo.insert!()
  end

  test "dedupe_communications/1 removes rows with the same fingerprint" do
    insert_duplicate_communication!()
    insert_duplicate_communication!()

    assert Enforcement.count_communications() == 2

    summary = Dedupe.dedupe_communications()

    assert summary.deleted == 1
    assert summary.duplicate_groups == 1
    assert summary.fingerprints_backfilled == 1
    assert Enforcement.count_communications() == 1

    [comm] = Enforcement.list_communications()
    assert comm.source_fingerprint == Communication.fingerprint(communication_attrs())
  end

  test "dedupe_communications/1 keeps the row that already has source_fingerprint" do
    attrs = communication_attrs()
    fingerprint = Communication.fingerprint(attrs)

    older = insert_duplicate_communication!()

    {:ok, keeper} =
      Enforcement.create_communication(Map.merge(attrs, %{source_fingerprint: fingerprint}))

    summary = Dedupe.dedupe_communications()

    assert summary.deleted == 1
    assert Enforcement.count_communications() == 1
    refute Repo.get(Communication, older.id)
    assert Repo.get!(Communication, keeper.id).source_fingerprint == fingerprint
  end

  test "dry_run does not delete or update" do
    insert_duplicate_communication!()
    insert_duplicate_communication!()

    summary = Dedupe.dedupe_communications(dry_run: true)

    assert summary.dry_run
    assert summary.deleted == 1
    assert summary.fingerprints_backfilled == 1
    assert Enforcement.count_communications() == 2
  end
end
