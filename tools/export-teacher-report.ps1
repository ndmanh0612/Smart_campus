$ErrorActionPreference='Stop'
$path=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\output\Bao_cao_Tuan_1_Trinh_Thay_05_11.docx')).Path
$word=$null;$doc=$null;$count=0;$alerts=$null;$security=$null
try{
 $word=New-Object -ComObject Word.Application
 $count=$word.Documents.Count;$alerts=$word.DisplayAlerts;$security=$word.AutomationSecurity
 if($count -eq 0){$word.Visible=$false}
 $word.DisplayAlerts=0;$word.AutomationSecurity=3
 $doc=$word.Documents.Open($path,$false,$false,$false)
 $doc.Fields.Update() | Out-Null;$doc.Repaginate();$doc.Save()
 $doc.ExportAsFixedFormat([IO.Path]::ChangeExtension($path,'.pdf'),17)
 [pscustomobject]@{Pages=$doc.ComputeStatistics(2);Report=$path}|ConvertTo-Json
}finally{
 if($doc){$doc.Close(0);[Runtime.InteropServices.Marshal]::ReleaseComObject($doc)|Out-Null}
 if($word){$word.DisplayAlerts=$alerts;$word.AutomationSecurity=$security;if($count -eq 0 -and $word.Documents.Count -eq 0){$word.Quit()};[Runtime.InteropServices.Marshal]::ReleaseComObject($word)|Out-Null}
}
