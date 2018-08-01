﻿Function Set-Column {
    <#
      .SYNOPSIS
        Adds a column to the existing data area in an Excel sheet, fills values and sets formatting
      .DESCRIPTION
        Set-Column takes a value which is either string containing a value or formula or a scriptblock
        which evaluates to a string, and optionally a column number and fills that value down the column.
        A column name can be specified and the new column can be made a named range.
        The column can be formatted.
      .Example
        C:> Set-Column -Worksheet $ws -Heading "WinsToFastLaps"  -Value {"=E$row/C$row"} -Column 7 -AutoSize -AutoNameRange
        Here $WS already contains a worksheet which contains counts of races won and fastest laps recorded by racing drivers (in columns C and E)
        Set-Column specifies that Column 7 should have a heading of "WinsToFastLaps" and the data cells should contain =E2/C2 , =E3/C3
        the data cells should become a named range, which will also be "WinsToFastLaps" the column width will be set automatically
    #>
    [cmdletbinding()]
    Param (
        [Parameter(ParameterSetName="Package",Mandatory=$true)]
        [OfficeOpenXml.ExcelPackage]$ExcelPackage,
        #The sheet to update can be a given as a name or an Excel Worksheet object - this sets it by name
        [Parameter(ParameterSetName="Package")]
        #The sheet to update can be a given as a name or an Excel Worksheet object - $workSheet contains the object
        $Worksheetname = "Sheet1",
        [Parameter(ParameterSetName="sheet",Mandatory=$true)]
        [OfficeOpenXml.ExcelWorksheet]
        $Worksheet,
        #Column to fill down - first column is 1. 0 will be interpreted as first unused column
        $Column = 0 ,
        #First row to fill data in
        [Int]$StartRow ,
        #value, formula or script block for to fill in. Script block can use $row, $column [number], $ColumnName [letter(s)], $startRow, $startColumn, $endRow, $endColumn
        [parameter(Mandatory=$true)]
        $Value ,
        #Optional column heading
        $Heading ,
        #Number format to apply to cells e.g. "dd/MM/yyyy HH:mm", "Â£#,##0.00;[Red]-Â£#,##0.00", "0.00%" , "##/##" , "0.0E+0" etc
        [Alias("NFormat")]
        $NumberFormat,
        #Style of border to draw around the row
        [OfficeOpenXml.Style.ExcelBorderStyle]$BorderAround,
        #Colour for the text - if none specified it will be left as it it is
        [System.Drawing.Color]$FontColor,
        #Make text bold; use -Bold:$false to remove bold
        [switch]$Bold,
        #Make text italic;  use -Italic:$false to remove italic
        [switch]$Italic,
        #Underline the text using the underline style in -underline type;  use -Underline:$false to remove underlining
        [switch]$Underline,
        #Should Underline use single or double, normal or accounting mode : default is single normal
        [OfficeOpenXml.Style.ExcelUnderLineType]$UnderLineType = [OfficeOpenXml.Style.ExcelUnderLineType]::Single,
        #Strike through text; use -Strikethru:$false to remove Strike through
        [switch]$StrikeThru,
        #Subscript or superscript (or none)
        [OfficeOpenXml.Style.ExcelVerticalAlignmentFont]$FontShift,
        #Font to use - Excel defaults to Calibri
        [String]$FontName,
        #Point size for the text
        [float]$FontSize,
        #Change background colour
        [System.Drawing.Color]$BackgroundColor,
        #Background pattern - solid by default
        [OfficeOpenXml.Style.ExcelFillStyle]$BackgroundPattern = [OfficeOpenXml.Style.ExcelFillStyle]::Solid ,
        #Secondary colour for background pattern
        [Alias("PatternColour")]
        [System.Drawing.Color]$PatternColor,
        #Turn on text wrapping; use -WrapText:$false to turn off word wrapping
        [switch]$WrapText,
        #Position cell contents to left, right, center etc. default is 'General'
        [OfficeOpenXml.Style.ExcelHorizontalAlignment]$HorizontalAlignment,
        #Position cell contents to top bottom or centre
        [OfficeOpenXml.Style.ExcelVerticalAlignment]$VerticalAlignment,
        #Degrees to rotate text. Up to +90 for anti-clockwise ("upwards"), or to -90 for clockwise.
        [ValidateRange(-90, 90)]
        [int]$TextRotation ,
        #Autofit cells to width
        [Alias("AutoFit")]
        [Switch]$AutoSize,
        #Set cells to a fixed width, ignored if Autosize is specified
        [float]$Width,
        #Set the inserted data to be a named range (ignored if header is not specified)
        [Switch]$AutoNameRange,
        #If Sepecified returns the range of cells which affected
        [switch]$ReturnRange,
        #If Specified, return an ExcelPackage object to allow further work to be done on the file.
        [switch]$PassThru
    )
    #if we were passed a package object and a worksheet name , get the worksheet.
    if ($ExcelPackage)   {$Worksheet   = $ExcelPackage.Workbook.Worksheets[$Worksheetname] }

    #In a script block to build a formula, we may want any of corners or the columnname,
    #if column and startrow aren't specified, assume first unused column, and first row
    if (-not $StartRow)   {$startRow   = $Worksheet.Dimension.Start.Row    }
    $StartColumn                       = $Worksheet.Dimension.Start.Column
    $endColumn                         = $Worksheet.Dimension.End.Column
    $endRow                            = $Worksheet.Dimension.End.Row
    if ($Column  -lt 2 )  {$Column     = $endColumn    + 1 }
    $ColumnName = [OfficeOpenXml.ExcelCellAddress]::new(1,$column).Address -replace "1",""

    Write-Verbose -Message "Updating Column $ColumnName"
    #If there is a heading, insert it and use it as the name for a range (if we're creating one)
    if      ($Heading)                 {
                                         $Worksheet.Cells[$StartRow, $Column].Value = $heading
                                         $startRow ++
      if    ($AutoNameRange)           { $Worksheet.Names.Add(  $heading, ($Worksheet.Cells[$startrow, $Column, $endRow, $Column]) ) | Out-Null }
    }
    #Fill in the data
    if      ($PSBoundParameters.ContainsKey('value')) { foreach ($row in ($StartRow.. $endRow)) {
        if  ($Value -is [scriptblock]) { #re-create the script block otherwise variables from this function are out of scope.
             $cellData = & ([scriptblock]::create( $Value ))
             Write-Verbose  -Message     $cellData
        }
        else                           { $cellData = $Value}
        if  ($cellData -match "^=")    { $Worksheet.Cells[$Row, $Column].Formula                           = $cellData           }
        elseif ( [System.Uri]::IsWellFormedUriString($cellData , [System.UriKind]::Absolute)) {
            # Save a hyperlink : internal links can be in the form xl://sheet!E419 (use A1 as goto sheet), or xl://RangeName
            if ($cellData -match "^xl://internal/") {
                  $referenceAddress = $cellData -replace "^xl://internal/" , ""
                  $display          = $referenceAddress -replace "!A1$"    , ""
                  $h = New-Object -TypeName OfficeOpenXml.ExcelHyperLink -ArgumentList $referenceAddress , $display
                  $Worksheet.Cells[$Row, $Column].HyperLink = $h
            }
            else {$Worksheet.Cells[$Row, $Column].HyperLink = $cellData }
            $Worksheet.Cells[$Row, $Column].Style.Font.Color.SetColor([System.Drawing.Color]::Blue)
            $Worksheet.Cells[$Row, $Column].Style.Font.UnderLine = $true
        }
        else                           { $Worksheet.Cells[$Row, $Column].Value                             = $cellData           }
        if  ($cellData -is [datetime]) { $Worksheet.Cells[$Row, $Column].Style.Numberformat.Format         = 'm/d/yy h:mm'       } # This is not a custom format, but a preset recognized as date and localized.
    }}
    #region Apply formatting
    $params = @{}
    foreach ($p in @('Underline','Bold','Italic','StrikeThru','FontSize','FontShift','NumberFormat','TextRotation',
                     'WrapText', 'HorizontalAlignment','VerticalAlignment', 'Autosize', 'Width', 'FontColor'
                     'BorderAround', 'BackgroundColor', 'BackgroundPattern', 'PatternColor')) {
        if ($PSBoundParameters.ContainsKey($p)) {$params[$p] = $PSBoundParameters[$p]}
    }
    $theRange = "$ColumnName$startRow`:$ColumnName$endRow"
    if ($params.Count) {
        Set-Format -WorkSheet $Worksheet -Range $theRange @params
    }
    #endregion
    #return the new data if -passthru was specified.
    if     ($passThru)                 { $Worksheet.Column(     $Column)}
    elseif ($ReturnRange)              { $theRange}
}