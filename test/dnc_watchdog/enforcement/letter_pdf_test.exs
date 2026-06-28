defmodule DncWatchdog.Enforcement.LetterPdfTest do
  use DncWatchdog.DataCase

  alias DncWatchdog.Enforcement
  alias DncWatchdog.Enforcement.EvidenceStorage
  alias DncWatchdog.Enforcement.LetterPdf
  import DncWatchdog.EnforcementFixtures

  test "build_html/2 embeds letter text and image exhibits" do
    case = case_fixture()
    png = <<137, 80, 78, 71, 45>>

    attachment =
      Enforcement.create_evidence_attachment!(%{
        case_id: case.id,
        filename: "screenshot.png",
        content_type: "image/png",
        storage_path: "uploads/evidence/#{case.id}/screenshot.png",
        caption: "SMS screenshot"
      })

    absolute = EvidenceStorage.absolute_path(attachment)
    File.mkdir_p!(Path.dirname(absolute))
    File.write!(absolute, png)

    letter = """
    Jane Doe
    123 Main St

    VIA CERTIFIED MAIL

    Appendix: Documented Contacts

    | Date & Time | Channel |
    | --- | --- |
    | 2026-05-20 09:14:00 | sms |
    """

    html = LetterPdf.build_html(letter, [attachment])

    assert html =~ "Jane Doe"
    assert html =~ "123 Main St"
    assert html =~ "Exhibit A"
    assert html =~ "SMS screenshot"
    assert html =~ "data:image/png;base64,"
    assert html =~ "<table>"
    assert html =~ "2026-05-20 09:14:00"
  end

  test "ensure_chromic_pdf!/0 is ok when ChromicPDF is running" do
    assert :ok = LetterPdf.ensure_chromic_pdf!()
  end
end
