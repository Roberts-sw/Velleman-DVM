package require Tcl 8.5;# lassign

proc = args {expr {*}$args}
proc max {a b} {if {$a>=$b} {return $a} {return $b}}
proc min {a b} {if {$a<=$b} {return $a} {return $b}}
proc data2serie args {
    # splits en verwijder voorloopnullen: 20JJ-MM-DD uu:mm:ss.ttt wwww ...
    foreach {datum tijd waarde} $args {break}
    lassign [split $datum -] J M D
    set J [= $J%400]    ;set M [scan $M %d] ;set D [scan $D %d]
    lassign [split $tijd :] u m s
    set u [scan $u %d]  ;set m [scan $m %d] ;set s [scan $s %d]

    # maak volgnummers aan voor dag en tijd
    set dagnr [= ($J-1)*365 + ($J-1)/4]
    switch -- $M {
        1   { }
        2   {incr dagnr 31}
    default {incr dagnr [= ($M+1)*153/5 - ($J&3 ? 63 : 62)]}
    }       ;incr dagnr [= $D-1+36892];# 36892 ==> 01-jan-2001 00:00:00
    set tijdnr [= (($u*60)+$m)*60+$s];# [s]

    # combineer dagnr/tijdnr en waarde
    return "[= $dagnr*86400+$tijdnr] $waarde"
voorbeelden:
(R) % data2serie 2021-08-16 14:50:45.46 0091    TMP  ?  1800
3838287045 0091
(R) % data2serie 2021-08-16 14:50:34.906    0,051   ACV  V  6,000
3838287034 0,051
}
proc filedo args {  ;# https://wiki.tcl-lang.org/page/withOpenFile
    if {[llength $args]<3} {
        error {wrong # args: should be "filedo fh fname ?access? ?permissions? script"}
    };  upvar 1 [lindex $args 0] fh
    try {open {*}[lrange $args 1 end-1]
    } on ok fh {uplevel 1 [lindex $args end]
    } finally { catch {chan close $fh}
    }
}
proc Vnet {bestand} {
    # Spoel1_50volt_49,85Krachtstr_Wisselmeting.TXT ==> 49,85V
    set bestand [string range $bestand 0 [string first K $bestand]-1]V
    string range $bestand [string last _ $bestand]+1 end
}
proc bestanden {m dir} {;# m - methode 0|1|2 == eerste|laatste|middeling
    cd $dir
    
    # per subdir sd: nummer x + spoelnaam sn
    foreach sd [glob -type d *] {
        cd $dir/$sd ;# puts "==> subdir: $sd"
        set x [lindex $sd 1];set sn [lindex $sd 2];set sdn Spoel[set x]_
    
        # per ingestelde spanning, sorteer bestanden: Temp < Wissel
        foreach spanning {50 100 150 200 250} {
            set bn $sdn$spanning*;set sdfiles [lsort [glob -type f $bn.TXT]]
            foreach i {0 1} {
                set bestand [lindex $sdfiles $i]    ;# puts $bestand
                set data [filedo fh $bestand r {chan read $fh}];set fdat$i ""
                foreach reg [split $data \n] {
                    if [llength $reg] {lappend fdat$i [data2serie {*}$reg]}
                }
            }
            # doorloop T en V tussen begin-/eindtijd t/te
            set combi "t T V n\n"
            set t [max [lindex $fdat0 {0 0}] [lindex $fdat1 {0 0}]]
            set te [min [lindex $fdat0 {end 0}] [lindex $fdat1 {end 0}]]
            for {set i 0;set ie [llength $fdat0]} {$i<$ie} {incr i} {
                if {[lindex $fdat0 "$i 0"]>=$t} {break}             }
            for {set j 0;set je [llength $fdat1]} {$j<$je} {incr j} {
                if {[lindex $fdat1 "$j 0"]>=$t} {break}             }
            set Tv [scan [lindex $fdat0 "$i 1"] %d];# zonder voorloop-'0'
            for {} {$t<$te} {set t $t1;set Tv $T} {
                # a) zoek tijdstippen totdat T != Tv
                for {set T $Tv} {[incr i]<$ie && $T==$Tv} {} {
                    set t1 [lindex $fdat0 "$i 0"]
                    set T [scan [lindex $fdat0 "$i 1"] %d];# zonder voorloop-'0'
                }
                # b) bepaal V met methode m vanaf t tot t1
                for {set n 0;set V 0} {$j<$je} {incr j} {
                    if {$t>[set tj [lindex $fdat1 "$j 0"]]} {continue}
                    set Vn [string map {, .} [lindex $fdat1 "$j 1"]]
                    if {2==$m} {incr n;set V [= $V+$Vn]} {
                        if {$m+!$n} {set n 1;set V $Vn}  }
                    if {$tj>=$t1} {if {2==$m} {set V [= $V/$n]};break}
                }
                # c) voeg toe aan combi, kap cijfers af
                if {$m<2 || 10<=$n} {
                    set dt [format %.7f [= $t/86400.]];set V [format %.4f $V]
                    append combi "$dt $Tv $V $n\n"
                }
            }
            # zet weg in csv-bestand, bv: ZMPT106B_49,85V_1.csv
            set fname [set sn]_[Vnet $bestand]_$m.csv
            set fdat [string map {. ,} [join [split $combi \ ] ";"]]
            filedo fh $fname w {chan puts $fh $fdat}
        }
    }
}
