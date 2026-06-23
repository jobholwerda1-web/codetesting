Attribute VB_Name = "LCB_MaakMappen"
Option Explicit

' ============================================================
' LCB MAPPENSTRUCTUUR SCRIPT
' Structuur: Zorgsoort > LCB > Versie
' - Alleen nieuwe rijen worden verwerkt (Status <> "Ja")
' - Hyperlink naar aangemaakte map wordt in Excel gezet (SharePoint URL)
' - Optionele dossierkoppeling wordt als Dossier.url in de map geplaatst
'
' EXCEL SHEET INDELING:
' Rij 1:  A="Basismap"        B=[SharePoint URL van de basismap, bijv. https://asrnl.sharepoint.com/sites/.../General]
' Rij 2:  A="RelatiefPad"     B=[lokaal pad relatief aan OneDriveCommercial, bijv. General - LCB Projectomgeving]
' Rij 3:  (leeg)
' Rij 4:  KOPPEN: A=Zorgsoort | B=LCB | C=Versie | D=Dossierkoppeling | E=Aangemaakt | F=Maplink
' Rij 5+: Data
'
' Maplink wordt opgeslagen als SharePoint hyperlink-formaat: "URL, Weergavetekst"
' ============================================================

Public Sub MaakLCBMappen()

    On Error GoTo EH

    Dim ws As Worksheet
    Set ws = ActiveSheet

    ' ------------------------
    ' Config ophalen
    ' ------------------------
    Dim baseInput As String, relPad As String, spBase As String
    baseInput = GetValueRightOfLabel(ws, "Basismap", 1)
    relPad    = GetValueRightOfLabel(ws, "RelatiefPad", 1)

    If baseInput = "" Then Err.Raise 1, , "Basismap ontbreekt in cel B1"
    If relPad = ""    Then Err.Raise 2, , "RelatiefPad ontbreekt in cel B2"

    ' SharePoint basismap: gebruik de waarde uit Basismap als die begint met http,
    ' anders geen SharePoint URL beschikbaar
    If LCase(Left(baseInput, 4)) = "http" Then
        spBase = baseInput
        ' trailing slash verwijderen voor consistente opbouw
        If Right(spBase, 1) = "/" Then spBase = Left(spBase, Len(spBase) - 1)
    End If

    Dim baseRoot As String
    baseRoot = ResolveBasePath(baseInput, relPad)

    If Not FolderExists(baseRoot) Then _
        Err.Raise 3, , "Basismap niet gevonden op lokale schijf:" & vbCrLf & baseRoot

    ' ------------------------
    ' Tabel zoeken op koptekst
    ' ------------------------
    Dim headerRow As Long
    headerRow = FindLabelRow(ws, "Zorgsoort", 1)
    If headerRow = 0 Then Err.Raise 4, , "Koptekst 'Zorgsoort' niet gevonden in kolom A"

    ' Kolomindeling (1-based, dus A=1)
    Const COL_ZORGSOORT As Long = 1
    Const COL_LCB       As Long = 2
    Const COL_VERSIE    As Long = 3
    Const COL_DOSSIER   As Long = 4
    Const COL_STATUS    As Long = 5
    Const COL_MAPLINK   As Long = 6

    Dim r           As Long
    Dim aangemaakt  As Long
    Dim fouten      As Long
    aangemaakt = 0
    fouten     = 0

    r = headerRow + 1

    ' ------------------------
    ' Rijen verwerken
    ' ------------------------
    Do While Trim(ws.Cells(r, COL_ZORGSOORT).Value) <> ""

        If Trim(ws.Cells(r, COL_STATUS).Value) <> "Ja" Then

            Dim zorgsoort   As String
            Dim lcbNaam     As String
            Dim versie      As String
            Dim dossierLink As String

            zorgsoort   = SanitizeFolderName(CStr(ws.Cells(r, COL_ZORGSOORT).Value))
            lcbNaam     = SanitizeFolderName(CStr(ws.Cells(r, COL_LCB).Value))
            versie      = SanitizeFolderName(CStr(ws.Cells(r, COL_VERSIE).Value))
            dossierLink = Trim(CStr(ws.Cells(r, COL_DOSSIER).Value))

            If zorgsoort = "" Or lcbNaam = "" Or versie = "" Then

                ws.Cells(r, COL_STATUS).Value = "Fout: veld leeg"
                fouten = fouten + 1

            Else

                Dim pad1 As String, pad2 As String, pad3 As String
                pad1 = CombinePath(baseRoot, zorgsoort)
                pad2 = CombinePath(pad1, lcbNaam)
                pad3 = CombinePath(pad2, versie)

                EnsureFolderExists pad1
                EnsureFolderExists pad2
                EnsureFolderExists pad3

                ' Dossierkoppeling als .url bestand in de versiemap
                If dossierLink <> "" Then
                    CreateUrlShortcut CombinePath(pad3, "Dossier.url"), dossierLink
                End If

                ' Maplink opslaan als SharePoint hyperlink-formaat: "URL, Weergavetekst"
                Dim weergave As String
                weergave = zorgsoort & " \ " & lcbNaam & " \ " & versie

                If spBase <> "" Then
                    ' SharePoint URL tot op LCB-niveau (niet dieper dan LCB-map)
                    Dim spUrl As String
                    spUrl = spBase & "/" & UrlEncodePart(zorgsoort) & "/" & UrlEncodePart(lcbNaam)
                    ws.Cells(r, COL_MAPLINK).Value = spUrl & ", " & weergave
                Else
                    ' Geen SharePoint URL beschikbaar: lokaal pad opslaan
                    ws.Cells(r, COL_MAPLINK).Value = pad3 & ", " & weergave
                End If

                ws.Cells(r, COL_STATUS).Value = "Ja"
                aangemaakt = aangemaakt + 1

            End If

        End If

        r = r + 1
    Loop

    ' ------------------------
    ' Eindmelding
    ' ------------------------
    Dim msg As String
    If aangemaakt = 0 And fouten = 0 Then
        msg = "Geen nieuwe mappen aangemaakt." & vbCrLf & _
              "Alle rijen zijn al verwerkt of er zijn geen rijen aanwezig."
        MsgBox msg, vbInformation, "LCB Mappen"
    Else
        msg = aangemaakt & " map(pen) aangemaakt onder:" & vbCrLf & baseRoot
        If fouten > 0 Then
            msg = msg & vbCrLf & vbCrLf & fouten & " rij(en) overgeslagen wegens lege velden."
        End If
        MsgBox msg, vbInformation, "LCB Mappen"
    End If

    Exit Sub

EH:
    MsgBox "Fout (rij " & r & "): " & Err.Description, vbCritical, "LCB Script"

End Sub


' ============================================================
' URL SHORTCUT AANMAKEN (.url bestand)
' Opent de URL in de standaardbrowser wanneer dubbelgeklikt.
' ============================================================
Private Sub CreateUrlShortcut(ByVal filePath As String, ByVal url As String)

    Dim iFile As Integer
    iFile = FreeFile

    Open filePath For Output As #iFile
    Print #iFile, "[InternetShortcut]"
    Print #iFile, "URL=" & url
    Close #iFile

End Sub


' ============================================================
' PAD HELPERS
' ============================================================

' SharePoint URL -> lokaal OneDrive-pad via omgevingsvariabele
Private Function ResolveBasePath(ByVal baseInput As String, ByVal relPad As String) As String
    If LCase(Left(baseInput, 4)) <> "http" Then
        ResolveBasePath = baseInput
    Else
        ResolveBasePath = CombinePath(Environ("OneDriveCommercial"), relPad)
    End If
End Function

Private Function CombinePath(ByVal p1 As String, ByVal p2 As String) As String
    If Right(p1, 1) <> "\" Then p1 = p1 & "\"
    CombinePath = p1 & p2
End Function


' ============================================================
' BESTANDSSYSTEEM
' ============================================================
Private Function FolderExists(ByVal path As String) As Boolean
    FolderExists = (Len(Dir(path, vbDirectory)) > 0)
End Function

Private Sub EnsureFolderExists(ByVal path As String)
    If Not FolderExists(path) Then MkDir path
End Sub


' ============================================================
' EXCEL INPUT HELPERS
' ============================================================
Private Function FindLabelRow(ws As Worksheet, label As String, col As Long) As Long
    Dim i As Long
    For i = 1 To 1000
        If Trim(CStr(ws.Cells(i, col).Value)) = label Then
            FindLabelRow = i
            Exit Function
        End If
    Next i
End Function

Private Function GetValueRightOfLabel(ws As Worksheet, label As String, col As Long) As String
    Dim r As Long
    r = FindLabelRow(ws, label, col)
    If r = 0 Then Exit Function
    GetValueRightOfLabel = Trim(CStr(ws.Cells(r, col + 1).Value))
End Function


' ============================================================
' URL ENCODING (spaties en bijzondere tekens voor SharePoint URL)
' ============================================================
Private Function UrlEncodePart(ByVal s As String) As String
    s = Replace(s, " ", "%20")
    s = Replace(s, "&", "%26")
    s = Replace(s, "#", "%23")
    s = Replace(s, "+", "%2B")
    UrlEncodePart = s
End Function


' ============================================================
' MAPNAAM SANITIZER
' ============================================================
Private Function SanitizeFolderName(s As String) As String
    s = Replace(s, ":", " -")
    s = Replace(s, "\", " ")
    s = Replace(s, "/", " ")
    s = Replace(s, "*", " ")
    s = Replace(s, "?", " ")
    s = Replace(s, """", " ")
    s = Replace(s, "<", " ")
    s = Replace(s, ">", " ")
    s = Replace(s, "|", " ")
    SanitizeFolderName = Trim(s)
End Function
