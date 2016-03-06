#!/bin/bash
CURDIR=`pwd`
historydir=~/.firebot/history
listin=/tmp/list.in.$$
cd $historydir
ls -tl *-????????.txt | awk '{system("head "  $9)}' | sort -t ';' -r -n -k 7 > $listin
cat $listin | head -30 | \
             awk -F ';' '{cputime="Benchmark time: "$9" s";\
                          if($9=="")cputime="";\
                          font="<font color=\"#00FF00\">";\
                          if($8=="2")font="<font color=\"#FF00FF\">";\
                          if($8=="3")font="<font color=\"#FF0000\">";\
                          printf("<p><a href=\"https://github.com/firemodels/fds-smv/commit/%s\">Revision: %s</a>%s %s</font><br>\n",$4,$5,font,$1);\
                          if($9!="")printf("%s <br>\n",cputime);\
                          printf("%s\n",$2);}' 
rm $listin
cd $CURDIR