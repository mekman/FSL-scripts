#!/bin/bash
# tksurfer wrapper.

# Written by Andreas Heckel
# University of Heidelberg
# heckelandreas@googlemail.com
# https://github.com/ahheckel
# 04/16/2014

Usage() {
    echo ""
    echo "Usage:   $(basename $0) [-s subject] <path to FS significance map 1> <path to FS significance map 2> [...]"
    echo "Example: $(basename $0) ./sessions/ss1_01/bold/anal/AvsB/sig-0-lh.w ./sessions/ss1_02/bold/anal/AvsB/sig-0-lh.w"
    echo "         $(basename $0) -s fsaverage ./sessions/ss1_01/bold/anal/AvsB/sig-0-lh.w ./sessions/ss1_02/bold/anal/AvsB/sig-0-lh.w"
    echo ""
    echo "Note:    a) assumes default Freesurfer directory structure (subjects located under directory named 'subjects'"
    echo "            and sessions located under directory named 'sessions')"
    echo "         b) assumes that <sessionname> = <subjectname> -or-"
    echo "                         <sessionname> = <subjectname>_<string|number>"
    echo "         c) <subjectname> must not contain underscores"
    echo ""
    exit 1
}

if [ "$1" = "-s" ] ; then
  shift
  _subject="$1"
  shift
else
  _subject=""
fi

[ "$1" = "" ] && Usage

FILE_PATHS="$@"

# create unique dir. for temporary files
tmpdir=$(mktemp -d -t $(basename $0)_XXXXXXXXXX)

# define exit trap
trap "rm -f $tmpdir/* ; rmdir $tmpdir ; exit" EXIT

if [ x"$flatpatch" = "x" ] ; then flatpatch=0 ; fi

counter=0
for i in $FILE_PATHS ; do

  if [ $(echo $i | grep ^/ | wc -l) -eq 0 ] ; then
    i=`pwd`/$i
    i=$(echo $i | sed "s|/\./|/|g" | sed "s|/\+|/|g") # remove '/./'and duplicate '/'
  fi

  #tmpfile=$tmpdir/$(basename $0)_$(basename $i)
  counter=$[$counter+1]
  tmpfile=$tmpdir/$$_$(basename $0)_${counter}

  # add tcl-scripting commands
  echo "set gaLinkedVars(redrawlockflag) 1" > ${tmpfile}.tcl
  echo "SendLinkedVarGroup redrawlock" >> ${tmpfile}.tcl
  echo "set gaLinkedVars(ignorezeroesinhistogramflag) 1" >> ${tmpfile}.tcl
  echo "SendLinkedVarGroup overlay" >> ${tmpfile}.tcl
  if [ $flatpatch -eq 1 ] ; then
    echo "scale_brain 0.75" >> ${tmpfile}.tcl
  fi

  vollist_lh=""   ; vollist_rh=""
  surflist_lh=""  ; surflist_rh=""
  overlist_lh=""  ; overlist_rh=""
  annotlist_lh="" ; annotlist_rh=""
  labels_lh=""    ; labels_rh=""
  sigmap=0
  session=""
  subject=$_subject

  niigz=$(echo $i | grep "\.nii.gz$" | wc -l)
  nii=$(echo $i | grep "\.nii$" | wc -l)
  mgh=$(echo $i | grep "\.mgh$" | wc -l)
  mgz=$(echo $i | grep "\.mgz$" | wc -l)
  
  label=$(echo $i | grep "\.label$" | wc -l)  
  patch=$(echo $i | grep "\.patch\." | wc -l)  
  annot=$(echo $i | grep "\.annot$" | wc -l)
  sphere=$(echo $i | grep "\.sphere$" | wc -l)
  
  sig=$(echo $(basename $i) | grep "sig\.mgh$" | wc -l)
  if [ $sig -eq 0 ] ; then
    sig=$(echo $(basename $i) | grep "^sig-0-" | wc -l) # for Freesurfer v4 FSFAST
  fi
  F=$(echo $(basename $i) | grep "^F\.mgh$" | wc -l)
  gamma=$(echo $(basename $i) | grep "^gamma\.mgh$" | wc -l)
  gammavar=$(echo $(basename $i) | grep "^gammavar\.mgh$" | wc -l)
  cnr=$(echo $(basename $i) | grep "^cnr\.mgh$" | wc -l)

  if [ $mgz -eq 0 ] ; then
    mri_info $i > $tmpfile
    type=$(cat $tmpfile | grep type: | head -n1 | cut -d : -f 2)  
    isscalar=$(cat $tmpfile | grep dimensions | cut -d : -f 2- | grep "x 1 x 1" | wc -l)
    rm $tmpfile
  else
    type=XXX
    isscalar=0
  fi

  # left or right hemisphere ?
  lh=0 ; rh=0
  lh="$(echo $(basename $i) | grep "\.lh\." | wc -l )"
  rh="$(echo $(basename $i) | grep "\.rh\." | wc -l )"
  if [ $lh -eq 0 ] ; then lh="$(echo $(basename $i) | grep "^lh\." | wc -l )" ; fi
  if [ $rh -eq 0 ] ; then rh="$(echo $(basename $i) | grep "^rh\." | wc -l )" ; fi
  if [ $lh -eq 0 ] ; then lh="$(echo $(basename $i) | grep "\.lh$" | wc -l )" ; fi
  if [ $rh -eq 0 ] ; then rh="$(echo $(basename $i) | grep "\.rh$" | wc -l )" ; fi
  if [ $lh -eq 0 ] ; then lh="$(echo $(basename $i) | grep "\-lh\." | wc -l )" ; fi
  if [ $rh -eq 0 ] ; then rh="$(echo $(basename $i) | grep "\-rh\." | wc -l )" ; fi
  if [ $lh -eq 0 ] ; then lh="$(echo $(basename $i) | grep "^lh[A-Z]" | wc -l )" ; fi
  if [ $rh -eq 0 ] ; then rh="$(echo $(basename $i) | grep "^rh[A-Z]" | wc -l )" ; fi
  _dir="$i"
  while [ $lh -eq 0 -a $rh -eq 0 ] ; do
    _dir=$(dirname $_dir) ; if [ "$_dir" = "$(dirname $_dir)" ] ; then break ; fi
    _dirname=$(basename $_dir)
    _hemi="$(basename $_dirname)"
    lh=$(echo $_hemi | grep "^lh\."  | wc -l)
    rh=$(echo $_hemi | grep "^rh\."  | wc -l)    
    if [ $lh -eq 0 ] ; then lh=$(echo $_hemi | grep "\.lh$"  | wc -l) ; fi
    if [ $rh -eq 0 ] ; then rh=$(echo $_hemi | grep "\.rh$"  | wc -l) ; fi
    if [ $lh -eq 0 ] ; then lh=$(echo $_hemi | grep "\.lh\." | wc -l) ; fi
    if [ $rh -eq 0 ] ; then rh=$(echo $_hemi | grep "\.rh\." | wc -l) ; fi
    if [ $lh -eq 0 ] ; then lh=$(echo $_hemi | grep "\-lh\-" | wc -l) ; fi
    if [ $rh -eq 0 ] ; then rh=$(echo $_hemi | grep "\-rh\-" | wc -l) ; fi
    if [ $lh -eq 0 ] ; then lh=$(echo $_hemi | grep "^lh[A-Z]" | wc -l ) ; fi
    if [ $rh -eq 0 ] ; then rh=$(echo $_hemi | grep "^rh[A-Z]" | wc -l ) ; fi
  done
  
  # check
  #zenity --info --text="$rh $lh"
  
  if [ $sig -eq 1 -o $F -eq 1 ] ; then # file is a significance map...
    sigmap=1
    if [ $lh -eq 1 ] ; then # ...of the left hemi.
      overlist_lh=$overlist_lh" -overlay $i -fminmax P_VAL_MIN P_VAL_MAX"
    elif [ $rh -eq 1 ] ; then # ...of the right hemi.
      overlist_rh=$overlist_rh" -overlay $i -fminmax P_VAL_MIN P_VAL_MAX"
    fi
  elif [ $type = "MGH" -a $isscalar -eq 1 ] ; then # file is (probably) a scalar
    if [ $lh -eq 1 ] ; then # ...of the left hemi.
      overlist_lh=$overlist_lh" -overlay $i"
    elif [ $rh -eq 1 ] ; then # ...of the right hemi.
      overlist_rh=$overlist_rh" -overlay $i"
    fi  
  fi
  
  if [ $label -eq 1 ] ; then # file is a label...
    echo "labl_load $i" >> ${tmpfile}.tcl # tcl-script: load label
  fi
  
  if [ $patch -eq 1 ] ; then # file is a patch...
    patchSel="-patch $i"
  fi
  
  if [ $sphere -eq 1 ] ; then # file is a sphere...
    surftype=sphere
  else 
    surftype=inflated
  fi
  
  # recursively searching for sessions/subjects directory (assuming 'sessions' and 'subjects' as names)
  if [ x"$subject" = "x" ] ; then  
    _dir="$i"
    while [ x"$subject" = "x" ] ; do
      _dir=$(dirname $_dir) ; if [ "$_dir" = "$(dirname $_dir)" ] ; then break ; fi
      _dirname=$(basename $_dir)
      _pardirname=$(basename $(dirname $_dir))    
      if [ "$_pardirname" = "sessions" ] ; then 
        subject=$_dirname
        session=$_dirname
        SUBJECTS_DIR=$(dirname $(dirname $_dir))/subjects
        if [ ! -d $SUBJECTS_DIR/$subject ] ; then
          subject=$(echo $subject | cut -d _ -f 1)
          #zenity --info --text=$subject
          #zenity --info --text=$SUBJECTS_DIR
        fi
      elif [ "$_pardirname" = "subjects" ] ; then
        subject=$_dirname
        SUBJECTS_DIR=$(dirname $_dir)    
      fi
      #zenity --info --text="$_dir"
    done  
    if [ x"$subject" = "x" ] ; then echo "Variable \$subject is empty - exiting." ; exit 1 ; fi
  fi

  # define annotations (only if no labels selected)
  if [ $(cat ${tmpfile}.tcl | grep labl_load | wc -l) -gt 0 ] ; then
    labelsunder=""
  else
    labelsunder="-labels-under"
    if [ ! -f $(dirname $(dirname $i))/label/lh.aparc.a2009s.annot ] ; then
      annotstr=aparc.a2005s.annot
    else
      annotstr=aparc.a2009s.annot
    fi
    annot_lh="-annotation $SUBJECTS_DIR/${subject}/label/lh.${annotstr} $labelsunder"
    annot_rh="-annotation $SUBJECTS_DIR/${subject}/label/rh.${annotstr} $labelsunder"
  fi

  # define commando
  if [ $lh -eq 1 ] ; then
    if [ $flatpatch -eq 1 ] ; then flatpatchBrain="-patch $SUBJECTS_DIR/${subject}/surf/lh.cortex.patch.flat" ; else flatpatchBrain="" ; fi
    cmd="tksurfer ${subject} lh $surftype $flatpatchBrain $patchSel -gray $annot_lh $overlist_lh -colscalebarflag 1 -colscaletext 1 -title $(basename $(dirname $(dirname $(dirname $i))))/$(basename $(dirname $(dirname $i)))/$(basename $(dirname $i))/$(basename $i) -tcl ${tmpfile}.tcl"
    #zenity --info --text="$cmd"
  elif [ $rh -eq 1 ] ; then
    if [ $flatpatch -eq 1 ] ; then flatpatchBrain="-patch $SUBJECTS_DIR/${subject}/surf/rh.cortex.patch.flat" ; else flatpatchBrain="" ; fi
    cmd="tksurfer ${subject} rh $surftype $flatpatchBrain $patchSel -gray $annot_rh $overlist_rh -colscalebarflag 1 -colscaletext 1 -title $(basename $(dirname $(dirname $(dirname $i))))/$(basename $(dirname $(dirname $i)))/$(basename $(dirname $i))/$(basename $i) -tcl ${tmpfile}.tcl"
  fi

  # execute in subshell
  if [ $sigmap -eq 1 ] ; then
    xterm -e /bin/bash -c "\
    echo \"file         = $(basename $i)\" ;\
    echo \"SUBJECTS_DIR = $SUBJECTS_DIR\" ;\
    echo \"subject      = $subject\" ;\
    echo \"session      = $session\" ;\
    echo \"left-hemi    = $lh\" ;\
    echo \"right-hemi   = $rh\" ;\
    echo \"------------------------------\" ;\
    echo \"Choose (or enter) a significance threshold:\" ;\
    echo -e \" a. p=0.050\n b. p=0.025\n c. p=0.010\n d. p=0.005\n\" ;\
    read -p \> s ;\
    echo \"------------------------------\" ;\
    if   [ \$s = a ] ; then logP1=1.3010 ; logP2=2  ;\
    elif [ \$s = b ] ; then logP1=1.6021 ; logP2=3  ;\
    elif [ \$s = c ] ; then logP1=2.0000 ; logP2=3  ;\
    elif [ \$s = d ] ; then logP1=2.3010 ; logP2=3  ;\
    else logP1=\$(echo \"l(\$s)/l(10)*-1\"|bc -l) ; logP2=\$(echo \"\$logP1+1\"|bc -l) ;\
    fi ;\
    echo \"p_min = \$logP1\" ;\
    echo \"p_max = \$logP2\" ;\
    echo \"------------------------------\" ;\
    echo \"------------------------------\" ;\
    cmd=\$(echo \"$cmd\" | sed \"s|P_VAL_MIN|\$logP1|g\" | sed \"s|P_VAL_MAX|\$logP2|g\") ;\
    echo \$cmd ;\
    echo \"------------------------------\" ;\
    echo \"------------------------------\" ;\
    \$cmd" &
  else
    xterm -e /bin/bash -c "\
    echo \"file         = $(basename $i)\" ;\
    echo \"SUBJECTS_DIR = $SUBJECTS_DIR\" ;\
    echo \"subject      = $subject\" ;\
    echo \"session      = $session\" ;\
    echo \"left-hemi    = $lh\" ;\
    echo \"right-hemi   = $rh\" ;\
    echo \"------------------------------\" ;\
    $cmd" &
  fi
done # end for loop

# info
read -p $(basename $0):\ When\ finished,\ press\ \<RETURN\>.

# kill bg jobs
kill $(jobs -p)
