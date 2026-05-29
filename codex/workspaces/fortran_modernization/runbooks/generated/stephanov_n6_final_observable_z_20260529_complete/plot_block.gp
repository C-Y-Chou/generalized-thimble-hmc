set terminal pngcairo size 1500,950 enhanced font 'Arial,12'
set datafile commentschars '#'
set grid
set key outside right center
set xlabel 'cycle prefix / mean samples per seed for all-available marker'
set style line 1 lc rgb '#1f77b4' lw 2 pt 7 ps 0.7
set style line 2 lc rgb '#d62728' lw 2 pt 7 ps 0.7
set style line 3 lc rgb '#1f77b4' lw 0 pt 9 ps 1.4
set style line 4 lc rgb '#d62728' lw 0 pt 9 ps 1.4
set style line 5 lc rgb '#2ca02c' lw 2 pt 7 ps 0.7
set style line 6 lc rgb '#2ca02c' lw 0 pt 9 ps 1.4
set output 'block500_estimator_trace.png'
set multiplot layout 2,2 title 'Block500 estimator traces'
set title 'chiral Re'
target=0.0244771982754
plot target with lines lc rgb '#444444' dt 2 title 'target', \
     'block500_withfb_chiral_Re.dat' using 1:2:3 with yerrorlines ls 1 title 'withfb block', \
     'block500_nofb_chiral_Re.dat' using 1:2:3 with yerrorlines ls 2 title 'nofb block'

set title 'chiral Im'
target=0
plot target with lines lc rgb '#444444' dt 2 title 'target', \
     'block500_withfb_chiral_Im.dat' using 1:2:3 with yerrorlines ls 1 title 'withfb block', \
     'block500_nofb_chiral_Im.dat' using 1:2:3 with yerrorlines ls 2 title 'nofb block'

set title 'density Re'
target=0.56611556665
plot target with lines lc rgb '#444444' dt 2 title 'target', \
     'block500_withfb_density_Re.dat' using 1:2:3 with yerrorlines ls 1 title 'withfb block', \
     'block500_nofb_density_Re.dat' using 1:2:3 with yerrorlines ls 2 title 'nofb block'

set title 'density Im'
target=0
plot target with lines lc rgb '#444444' dt 2 title 'target', \
     'block500_withfb_density_Im.dat' using 1:2:3 with yerrorlines ls 1 title 'withfb block', \
     'block500_nofb_density_Im.dat' using 1:2:3 with yerrorlines ls 2 title 'nofb block'
unset multiplot
