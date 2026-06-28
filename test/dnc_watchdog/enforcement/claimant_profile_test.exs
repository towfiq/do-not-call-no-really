defmodule DncWatchdog.Enforcement.ClaimantProfileTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.ClaimantProfile
  alias DncWatchdog.Enforcement.LetterDraft
  import DncWatchdog.EnforcementFixtures
  import DncWatchdog.SqliteFixtures

  test "update_claimant_profile/1 persists defaults used by letters" do
    assert {:ok, profile} =
             Enforcement.update_claimant_profile(%{
               name: "Jane Doe",
               address: "456 Elm St\nSan Jose, CA 95110",
               phone: "4085551212",
               email: "jane@example.com"
             })

    assert profile.address =~ "456 Elm St"

    case = case_fixture(%{claimant_name: nil, claimant_address: nil})
    comm = communication_fixture(%{case_id: case.id, violation_status: "violation"})

    body =
      LetterDraft.render(case, [comm], [],
        claimant_profile: Enforcement.get_claimant_profile()
      )

    assert body =~ "456 Elm St"
    assert body =~ "jane@example.com"
  end

  test "import_claimant_from_me_card/1 loads the Contacts Me card" do
    dir = temp_dir!("claimant_profile")
    path = create_me_card_contacts_db(Path.join(dir, "AddressBook-v22.abcddb"))

    assert {:ok, profile} = Enforcement.import_claimant_from_me_card(contacts_dbs: [path])
    assert profile.address == "123 Oak St\nPalo Alto, CA 94301"
    assert profile.email == "mark@example.com"
  end

  test "resolve/4 prefers explicit case values over saved profile" do
    profile = %ClaimantProfile{address: "Saved address"}

    assert ClaimantProfile.resolve(:address, nil, "Case address", profile) == "Case address"
  end
end
