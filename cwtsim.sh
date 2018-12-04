#!/bin/bash

# where is the rigctl command
rigctl=./rigctl

# device name
rigdevice=/dev/ttyUSB0
# rigctl device number
rig=373

# command to execute keyer
keyer="python ./keyer.py"
cwdevice=/dev/ttyUSB1

# total number of calls per speed floor
# number of elements must match speed_floors
distribution=( 3 10 4 )

# call speed will be between two speed floors
# e.g. if (20 30 40) the first speed range would be 20-30wpm, the next would be 30-40wpm
speed_floors=( 20 30 40 )
max_wpm=50

callfile=./cwops-members.txt

# setup base frequency, and how much to qsy for tone variation
base_freq=21040000
freq_range=200

# ---- dont touch anything below here :) ----
readkey() {
  local key settings
  settings=$(stty -g)             # save terminal settings
  stty -icanon -echo min 0        # disable buffering/echo, allow read to poll
  dd count=1 > /dev/null 2>&1     # Throw away anything currently in the buffer
  stty min 1                      # Don't allow read to poll anymore
  key=$(dd count=1 2> /dev/null)  # do a single read(2) call
  stty "$settings"                # restore terminal settings
  printf "%s" "$key"
}

# Get the F key sequences from termcap
# TERM has to be set correctly for this to work. 
f1=$(tput kf1)
f2=$(tput kf2)
f3=$(tput kf3)
f4=$(tput kf4)
f5=$(tput kf5)
f6=$(tput kf6)
f7=$(tput kf7)
f8=$(tput kf8)

speeds=()
freqs=()
calls=()
exchanges=()

num_floors=${#speed_floors[@]}
total_calls=0
for i in ${distribution[@]}
do
  let total_calls+=$i
done
echo "total calls: $total_calls"
echo $screen_break

for (( idx=0; idx<${num_floors}; idx++ ))
do
  next_idx=$((idx+1))
  min_speed=${speed_floors[$idx]}
  if [ $next_idx -eq ${num_floors} ]
  then 
     max_speed=$max_wpm
  else
    max_speed=${speed_floors[$idx+1]}
  fi

  for (( i=0; i<${distribution[$idx]}; i++ ))
  do
    offset=$(shuf -i 0-$freq_range -n 1)
    if (( RANDOM % 2 ))
    then 
     freq=$(( $base_freq+$offset ))
    else 
     freq=$(( $base_freq-$offset ))
    fi
    speed=$(shuf -i $min_speed-$max_speed -n 1)
    speeds+=($speed)
    freqs+=($freq)
  done

done
speeds=( $(shuf -e "${speeds[@]}") )
freqs=( $(shuf -e "${freqs[@]}") )

shuf -n $total_calls $callfile > tmpcalls
declare -a calldata
readarray calldata < tmpcalls 
for line in "${calldata[@]}"
do
  call=$(echo "$line" | cut -d',' -f1 )
  exchange=$(echo "$line" | cut -d',' -f2)
  calls+=($call)
  exchanges+=("$exchange")
done

i=0
stats=()
call_stat=0
exchange_stat=0
name_stat=0
qrs=0

# set initial speed and freq for this call
speed=${speeds[i]}
freq=${freqs[i]} 
command="F $freq"
$($rigctl -m $rig -r $rigdevice $command)

cur=$i
while true
do
  clear
  cur=$(( $i+1 ))
  echo "$cur of $total_calls"
  echo -e "speed: ${speeds[i]} \nfreq: ${freqs[i]}\ncall: ${calls[i]}\nexchange: ${exchanges[i]}"
  echo -e "\nstats:"
  echo -e "call: $call_stat\nexchange: $exchange_stat\nname: $name_stat\nqrs: $qrs\n"
  echo -e "F1) send call\nF2) send exchange\nF3) send name\nF4) send TU\nF5) QRS -5wpm\nF6) QRQ +5wpm\nF7) QRZ\nq) quit"
  echo -n ">"
  key=$(readkey)
  echo ""
  case "$key" in
  "$f1")
    $keyer -w $speed -d $cwdevice -t "${calls[i]}"
    let call_stat+=1
    continue
    ;; 
  "$f2")
    $keyer -w $speed -d $cwdevice -t "${exchanges[i]}"
    let exchange_stat+=1
    continue
    ;; 
  "$f3")
    name=$(echo "${exchanges[i]}" | cut -d' ' -f1)
    $keyer -w $speed -d $cwdevice -t "$name"
    let name_stat+=1
    continue
    ;; 
  "$f4")
    $keyer -w $speed -d $cwdevice -t "TU"
    continue
    ;; 
  "$f5")
    let qrs-=5
    let speed+=$qrs
    continue
    ;; 
  "$f6")
    let qrs+=5
    let speed+=$qrs
    continue
    ;; 
  "$f7")
    stats[$i]="call: $call_stat exchange: $exchange_stat name: $name_stat qrs: $qrs"
    let i+=1
    if [ $(($i)) -eq $total_calls ]
    then 
      break
    else
      call_stat=0
      exchange_stat=0
      name_stat=0
      qrs=0
      speed=${speeds[i]}
      freq=${freqs[i]} 
      command="F $freq"
      $($rigctl -m $rig -r $rigdevice $command)
      continue
    fi
    ;;
  'q')
    break
    ;;
    *)
    continue
    ;;    
  esac
done


for (( i=0; i<${total_calls}; i++))
do
 if test "${stats[i]+isset}"
 then 
   echo "speed: ${speeds[i]}  freq: ${freqs[i]} call: ${calls[i]} exchange: ${exchanges[i]}"
   echo -e "${stats[i]}\n"
 fi
done
rm tmpcalls
