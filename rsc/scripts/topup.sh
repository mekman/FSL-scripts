#!/bin/bash
# Wrapper for FSL's topup.

# Written by Andreas Heckel
# University of Heidelberg
# heckelandreas@googlemail.com
# https://github.com/ahheckel
# 10/02/2013

set -e

Usage() {
    echo ""
    echo "Usage: `basename $0` <out-dir> <isBOLD: 0|1> [n_dummyB0] <dwi-blip-> <dwi-blip+> <unwarp-dir> <TotalReadoutTime(s)> <use noec: 0|1> <use EDDY: 0|1> <use ec: 0|1> [<dof> <costfunction>] [<subj>] [<sess>]"
    echo "Example: topup.sh topupdir 0 \"dwi*+.nii.gz\" \"dwi*-.nii.gz\" -y 0.02975 1 0 1 12 corratio 01 a"
    echo "         topup.sh topupdir 1 4 \"bold*+.nii.gz\" \"bold*-.nii.gz\" +x 0.02975 1 0 1 6 mutualinfo 01 a"
    echo ""
    echo "NOTE:    -requires same number of blipup and blipdown images."
    echo "         -bvals/bvecs files are detected by suffix *_bvals and *_bvecs."
    echo "         -alphabetical listings of blipup/blipdown images (dwi*+, dwi*-) and bvals/bvecs must match !"
    echo "         -TotalReadoutTime(s): effectiveESP(ms) * (PhaseEncodingSteps - 1) ; e.g. 0.25ms * 119 / 1000"
    echo ""
    exit 1
}

[ "$7" = "" ] && Usage
outdir="$1"
isBOLD=$2
if [ $isBOLD -eq 1 ] ; then
  n_b0=$3
  shift
fi
pttrn_diffsminus="$3"
pttrn_diffsplus="$4"
uw_dir="$5"
TROT_topup=$6 # total readout time in seconds (EES_diff * (PhaseEncodingSteps - 1), i.e. 0.25 * 119 / 1000)
TOPUP_USE_NATIVE=$7
TOPUP_USE_EDDY=$8
TOPUP_USE_EC=$9
if [ $TOPUP_USE_EC -eq 1 ] ; then
  TOPUP_EC_DOF=${10} # degrees of freedom used by eddy-correction
  TOPUP_EC_COST=${11} # cost-function used by eddy-correction
  shift 2
fi
subj=${10} # optional
sess=${11} # optional

# source commonly used functions
source $(dirname $0)/globalfuncs

# set error trap
trap 'echo "$0 : An ERROR has occured."' ERR

# create temporary dir.
wdir=$(mktemp -d -t $(basename $0)_XXXXXXXXXX) # create unique dir. for temporary files
#wdir=/tmp/$(basename $0)_$$ ; mkdir -p $wdir

# create joblist file for SGE
echo "`basename $0`: touching SGE job control file in '$wdir'."
JIDfile="$wdir/$(basename $0)_$$.sge"
touch $JIDfile

# set exit trap
trap "set +e ; echo -e \"\n`basename $0`: cleanup: erasing Job-IDs in '$JIDfile'\" ; delJIDs $JIDfile ;  rm -f $wdir/* ; rmdir $wdir ; exit" EXIT

# display info
echo "`basename $0`: starting TOPUP..."

# check SGE
if [ x"$SGE_ROOT" != "x" ] ; then
  echo "`basename $0`: checking SGE..."
  qstat &>/dev/null
fi

# defines vars
if [ x"$subj" = "x" ] ; then subj="_" ; fi
if [ x"$sess" = "x" ] ; then sess="." ; fi
mkdir -p $outdir
echo $subj > $outdir/.subjects
echo $sess > $outdir/.sessions_struc
logdir=$outdir/logs ; mkdir -p $logdir
scriptdir=$(dirname $0)
tmpltdir=$scriptdir/templates
sdir=`pwd`

# define bval/bvec files
fldr=$outdir ; mkdir -p $fldr
ls $pttrn_diffsplus > $fldr/diff+.files
ls $pttrn_diffsminus > $fldr/diff-.files
rm -f $fldr/bvec+.files ; for i in $(cat $fldr/diff+.files) ; do echo $(remove_ext $i)_bvecs >> $fldr/bvec+.files  ; done
rm -f $fldr/bvec-.files ; for i in $(cat $fldr/diff-.files) ; do echo $(remove_ext $i)_bvecs >> $fldr/bvec-.files  ; done
rm -f $fldr/bval+.files ; for i in $(cat $fldr/diff+.files) ; do echo $(remove_ext $i)_bvals >> $fldr/bval+.files  ; done
rm -f $fldr/bval-.files ; for i in $(cat $fldr/diff-.files) ; do echo $(remove_ext $i)_bvals >> $fldr/bval-.files  ; done
cat $fldr/bvec-.files $fldr/bvec+.files > $fldr/bvec.files
cat $fldr/bval-.files $fldr/bval+.files > $fldr/bval.files

# create bval/bvec dummy files
for i in $(ls $pttrn_diffsplus) ; do
  i_bval=`remove_ext ${i}`_bvals
  i_bvec=`remove_ext ${i}`_bvecs  
  #if [ ! -f $(dirname $pttrn_diffsplus)/$i_bval -a ! -f $(dirname $pttrn_diffsplus)/$i_bvec ] ; then
  if [ $isBOLD -eq 1 ] ; then
      echo "`basename $0`: isBOLD=1 -> creating dummy bval/bvec files."
      if [ -f $i_bval ] ; then echo "`basename $0`: WARNING: '$i_bval' already exists - will overwrite..." ; fi
      if [ -f $i_bvec ] ; then echo "`basename $0`: WARNING: '$i_bvec' already exists - will overwrite..." ; fi
      cmd="$(dirname $0)/dummy_bvalbvec.sh $i $n_b0"
      echo $cmd ; $cmd
  fi
done
for i in $(ls $pttrn_diffsminus) ; do
  i_bval=`remove_ext ${i}`_bvals
  i_bvec=`remove_ext ${i}`_bvecs  
  #if [ ! -f $(dirname $pttrn_diffsminus)/$i_bval -a ! -f $(dirname $pttrn_diffsminus)/$i_bvec ] ; then
  if [ $isBOLD -eq 1 ] ; then
      #echo "'$i_bval' and '$i_bvec' not found..."
      echo "`basename $0`: isBOLD=1 -> creating dummy files."
      if [ -f $i_bval ] ; then echo "`basename $0`: WARNING: '$i_bval' already exists - will overwrite..." ; fi
      if [ -f $i_bvec ] ; then echo "`basename $0`: WARNING: '$i_bvec' already exists - will overwrite..." ; fi
      cmd="$(dirname $0)/dummy_bvalbvec.sh $i $n_b0"
      echo $cmd ; $cmd
  fi
done

# count input files
n_dwi_plus=$(cat $fldr/diff+.files | wc -l)
n_dwi_minus=$(cat $fldr/diff-.files | wc -l)
n_vec_plus=`cat $fldr/bvec+.files | wc -l`
n_vec_minus=`cat $fldr/bvec-.files | wc -l`
n_val_plus=`cat $fldr/bval+.files | wc -l`
n_val_minus=`cat $fldr/bval-.files | wc -l`

# enable stages
TOPUP_STG1=1
TOPUP_STG2=1
TOPUP_STG3=1               
TOPUP_STG4=1               
TOPUP_STG5=1               
TOPUP_STG6=1  

# display some info
echo "`basename $0`: TROT=$TROT_topup"
echo "`basename $0`: TOPUP_USE_NATIVE=$TOPUP_USE_NATIVE"
echo "`basename $0`: TOPUP_USE_EDDY=$TOPUP_USE_EDDY"
echo "`basename $0`: TOPUP_USE_EC=$TOPUP_USE_EC"
if [ $TOPUP_USE_EC -eq 1 ] ; then
  echo "`basename $0`: TOPUP_EC_DOF=$TOPUP_EC_DOF"
  echo "`basename $0`: TOPUP_EC_COST=$TOPUP_EC_COST"
fi
echo "`basename $0`: n_dwi- : $n_dwi_minus"
echo "`basename $0`: n_dwi+ : $n_dwi_plus"
echo "`basename $0`: n_bval-: $n_val_minus"
echo "`basename $0`: n_bval+: $n_val_plus"
echo "`basename $0`: n_bvec-: $n_vec_minus"
echo "`basename $0`: n_bvec+: $n_vec_plus"
echo "`basename $0`: TOPUP_STG1=$TOPUP_STG1"
echo "`basename $0`: TOPUP_STG2=$TOPUP_STG2"
echo "`basename $0`: TOPUP_STG3=$TOPUP_STG3"               
echo "`basename $0`: TOPUP_STG4=$TOPUP_STG4"               
echo "`basename $0`: TOPUP_STG5=$TOPUP_STG5"                              
echo "`basename $0`: TOPUP_STG6=$TOPUP_STG6"                              
echo ""

# check bvals, bvecs and dwi files for consistent number of entries
errflag=0
echo "TOPUP : Checking bvals/bvecs- and DWI files for consistent number of entries..."
for subj in `cat $outdir/.subjects` ; do
  for sess in `cat $outdir/.sessions_struc` ; do
    i=1
    for dwi_p in $(cat $fldr/diff+.files) ; do
      dwi_m=$(cat $fldr/diff-.files | sed -n ${i}p)
      n_bvalsplus=`cat $fldr/bval+.files | sed -n ${i}p | xargs cat | wc -w` ;  n_bvecsplus=`cat $fldr/bvec+.files | sed -n ${i}p | xargs cat | wc -w`
      n_bvalsminus=`cat $fldr/bval-.files | sed -n ${i}p | xargs cat | wc -w` ; n_bvecsminus=`cat $fldr/bvec-.files | sed -n ${i}p | xargs cat | wc -w`
      nvolplus=`countVols "$dwi_p"` ; nvolminus=`countVols "$dwi_m"`
      if [ $n_bvalsplus -eq $nvolplus -a $n_bvecsplus=$(echo "scale=0 ; 3*$n_bvalsplus" | bc -l) ] ; then 
        echo "TOPUP : subj $subj , sess $sess : $(basename $dwi_p) : consistent number of entries in bval/bvec/dwi files ($n_bvalsplus)"
      else
        echo "TOPUP : subj $subj , sess $sess : $(basename $dwi_p) : ERROR : inconsistent number of entries in bval:$n_bvalsplus / bvec:$(echo "scale=0; $n_bvecsplus/3" | bc -l) / dwi:$nvolplus" ; errflag=1
      fi
      if [ $n_bvalsminus -eq $nvolminus -a $n_bvecsminus=$(echo "scale=0 ; 3*$n_bvalsminus" | bc -l) ] ; then 
        echo "TOPUP : subj $subj , sess $sess : $(basename $dwi_m) : consistent number of entries in bval/bvec/dwi files ($n_bvalsminus)"
      else
        echo "TOPUP : subj $subj , sess $sess : $(basename $dwi_m) : ERROR : inconsistent number of entries in bval:$n_bvalsminus / bvec:$(echo "scale=0; $n_bvecsminus/3" | bc -l) / dwi:$nvolminus" ; errflag=1
      fi
      if [ $n_bvalsplus -eq $n_bvalsminus ] ; then 
        echo "TOPUP : subj $subj , sess $sess : blip(+/-) : consistent number of entries ($n_bvalsminus)"
      else
        echo "TOPUP : subj $subj , sess $sess : blip(+/-) : ERROR : inconsistent number of entries (+: $n_bvalsplus -: $n_bvalsminus)" ; errflag=1
      fi
      i=$[$i+1]
    done
  done
done
if [ $errflag -eq 1 ] ; then echo "DWI consistency check : Exiting due to errors !" ; exit 1 ; fi
n_bvalsplus="" ; n_bvalsminus="" ; n_bvecsplus="" ; n_bvecsminus="" ; nvolplus="" ; nvolminus="" ; errflag="" ; subj="" ; sess="" ; i="" ; dwi_m="" ; dwi_p=""
echo "TOPUP : ...done." ; echo ""
# end check 

#------------------------------

# TOPUP prepare
if [ $TOPUP_STG1 -eq 1 ] ; then
  echo "----- BEGIN TOPUP_STG1 -----"
   
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
    
      ## check if we have acquisition parameters
      #defineDWIparams config_acqparams_dwi $subj $sess
    
      if [ "x$pttrn_diffsplus" = "x" -o "x$pttrn_diffsminus" = "x" ] ; then
        echo "TOPUP : subj $subj , sess $sess : ERROR : file search pattern for blipUp/blipDown DWIs not set..."
        continue
      fi
      
      fldr=$outdir
      mkdir -p $fldr
      
      # display info
      echo "TOPUP : subj $subj , sess $sess : preparing TOPUP... "
      
      # are the +- diffusion files in equal number ?
      n_plus=`ls $pttrn_diffsplus | wc -l`
      n_minus=`ls $pttrn_diffsminus | wc -l`
      if [ ! $n_plus -eq $n_minus ] ; then 
        echo "TOPUP : subj $subj , sess $sess : ERROR : number of +blips diff. files ($n_plus) != number of -blips diff. files ($n_minus) - continuing loop..."
        continue
      elif [ $n_plus -eq 0 -a $n_minus -eq 0 ] ; then
        echo "TOPUP : subj $subj , sess $sess : ERROR : no blip-up/down diffusion files found for TOPUP (+/- must be part of the filename) - continuing loop..."
        continue
      fi
                        
      # count +/- bvec/bval-files
      n_vec_plus=`cat $fldr/bvec+.files | wc -l`
      n_vec_minus=`cat $fldr/bvec-.files | wc -l`
      n_val_plus=`cat $fldr/bval+.files | wc -l`
      n_val_minus=`cat $fldr/bval-.files | wc -l`
      
      # are the +/- bvec-files equal in number ?
      if [ ! $n_vec_plus -eq $n_vec_minus ] ; then 
        echo "TOPUP : subj $subj , sess $sess : ERROR : number of +blips bvec-files ($n_vec_plus) != number of -blips bvec-files ($n_vec_minus) - continuing loop..."
        continue
      elif [ $n_vec_plus -eq 0 -a $n_vec_minus -eq 0 ] ; then
        echo "TOPUP : subj $subj , sess $sess : ERROR : no blip-up/down bvec-files found for TOPUP (+/- must be part of the filename) - continuing loop..."
        continue
      fi
      
      # are the +/- bval-files equal in number ?
      if [ ! $n_val_plus -eq $n_val_minus ] ; then 
        echo "TOPUP : subj $subj , sess $sess : ERROR : number of +blips bval-files ($n_val_plus) != number of -blips bval-files ($n_val_minus) - continuing loop..."
        continue
      elif [ $n_val_plus -eq 0 -a $n_val_minus -eq 0 ] ; then
        echo "TOPUP : subj $subj , sess $sess : ERROR : no blip-up/down bval-files found for TOPUP (+/- must be part of the filename) - continuing loop..."
        continue
      fi
      
      # concatenate +bvecs and -bvecs
      concat_bvals "$(cat $fldr/bval-.files)" $fldr/bvals-_concat.txt
      concat_bvals "$(cat $fldr/bval+.files)" $fldr/bvals+_concat.txt 
      concat_bvecs "$(cat $fldr/bvec-.files)" $fldr/bvecs-_concat.txt
      concat_bvecs "$(cat $fldr/bvec+.files)" $fldr/bvecs+_concat.txt 

      nbvalsplus=$(wc -w $fldr/bvals+_concat.txt | cut -d " " -f 1)
      nbvalsminus=$(wc -w $fldr/bvals-_concat.txt | cut -d " " -f 1)
      nbvecsplus=$(wc -w $fldr/bvecs+_concat.txt | cut -d " " -f 1)
      nbvecsminus=$(wc -w $fldr/bvecs-_concat.txt | cut -d " " -f 1)      
     
      # check number of entries in concatenated bvals/bvecs files
      n_entries=`countVols "$pttrn_diffsplus"` 
      if [ $nbvalsplus = $nbvalsminus -a $nbvalsplus = $n_entries -a $nbvecsplus = `echo "3*$n_entries" | bc` -a $nbvecsplus = $nbvecsminus ] ; then
        echo "TOPUP : subj $subj , sess $sess : number of entries in bvals- and bvecs files consistent ($n_entries entries)."
      else
        echo "TOPUP : subj $subj , sess $sess : ERROR : number of entries in bvals- and bvecs files NOT consistent - continuing loop..."
        echo "(diffs+: $n_entries ; bvals+: $nbvalsplus ; bvals-: $nbvalsminus ; bvecs+: $nbvecsplus /3 ; bvecs-: $nbvecsminus /3)"
        continue
      fi
      
      # check if +/- bval entries are the same
      i=1
      for bval in `cat $fldr/bvals+_concat.txt` ; do
        if [ $bval != $(cat $fldr/bvals-_concat.txt | cut -d " " -f $i)  ] ; then 
          echo "TOPUP : subj $subj , sess $sess : ERROR : +bval entries do not match -bval entries (they should have the same values !) - exiting..."
          exit
        fi        
        i=$[$i+1]
      done
      
      # getting unwarp direction
      echo "TOPUP : subj $subj , sess $sess : unwarp direction is '$uw_dir'."
      x=0 ; y=0 ; z=0; 
      if [ "$uw_dir" = "+x" ] ; then x=1  ; fi
      if [ "$uw_dir" = "-x" ] ; then x=-1 ; fi
      if [ "$uw_dir" = "+y" ] ; then y=-1 ; fi # sic! (so that TOPUP and SIEMENS phasemaps match in sign)
      if [ "$uw_dir" = "-y" ] ; then y=1  ; fi # sic! (so that TOPUP and SIEMENS phasemaps match in sign)
      if [ "$uw_dir" = "+z" ] ; then z=1  ; fi
      if [ "$uw_dir" = "-z" ] ; then z=-1 ; fi
      mx=$(echo "scale=0; -1 * ${x}" | bc -l)
      my=$(echo "scale=0; -1 * ${y}" | bc -l)
      mz=$(echo "scale=0; -1 * ${z}" | bc -l)
      blipdownline="$mx $my $mz $TROT_topup"
      blipupline="$x $y $z $TROT_topup"
      
      # display info
      echo "TOPUP : subj $subj , sess $sess : example blip-down line:"
      echo "        $blipdownline"
      echo "TOPUP : subj $subj , sess $sess : example blip-up line:"
      echo "        $blipupline"
      
      # creating index file for TOPUP
      echo "TOPUP : subj $subj , sess $sess : creating index file for TOPUP..."      
      rm -f $fldr/$(subjsess)_acqparam.txt ; rm -f $fldr/$(subjsess)_acqparam_inv.txt ; rm -f $fldr/diff.files # clean-up previous runs...    
      diffsminus=`ls ${pttrn_diffsminus}`
      for file in $diffsminus ; do
        nvol=`fslinfo $file | grep ^dim4 | awk '{print $2}'`
        echo "$file n:${nvol}" | tee -a $fldr/diff.files
        for i in `seq 1 $nvol`; do
          echo "$blipdownline" >> $fldr/$(subjsess)_acqparam.txt
          echo "$blipupline" >> $fldr/$(subjsess)_acqparam_inv.txt
        done
      done
      
      diffsplus=`ls ${pttrn_diffsplus}`
      for file in $diffsplus ; do
        nvol=`fslinfo $file | grep ^dim4 | awk '{print $2}'`
        echo "$file n:${nvol}" | tee -a $fldr/diff.files
        for i in `seq 1 $nvol`; do
          echo "$blipupline" >> $fldr/$(subjsess)_acqparam.txt
          echo "$blipdownline" >> $fldr/$(subjsess)_acqparam_inv.txt
        done
      done
      
      ## creating index file for TOPUP
      #echo "TOPUP : subj $subj , sess $sess : creating index file for TOPUP..."      
      #rm -f $fldr/$(subjsess)_acqparam.txt ; rm -f $fldr/$(subjsess)_acqparam_inv.txt ; rm -f $fldr/diff.files # clean-up previous runs...
      
      #diffsminus=`ls ${pttrn_diffsminus}`
      #for file in $diffsminus ; do
        #nvol=`fslinfo $file | grep ^dim4 | awk '{print $2}'`
        #echo "$file n:${nvol}" | tee -a $fldr/diff.files
        #for i in `seq 1 $nvol`; do
          #echo "0 -1 0 $TROT_topup" >> $fldr/$(subjsess)_acqparam.txt
          #echo "0 1 0 $TROT_topup" >> $fldr/$(subjsess)_acqparam_inv.txt
        #done
      #done
      
      #diffsplus=`ls ${pttrn_diffsplus}`
      #for file in $diffsplus ; do
        #nvol=`fslinfo $file | grep ^dim4 | awk '{print $2}'`
        #echo "$file n:${nvol}" | tee -a $fldr/diff.files
        #for i in `seq 1 $nvol`; do
          #echo "0 1 0 $TROT_topup" >> $fldr/$(subjsess)_acqparam.txt
          #echo "0 -1 0 $TROT_topup" >> $fldr/$(subjsess)_acqparam_inv.txt
        #done
      #done
            
      # merging diffusion images for TOPUP    
      echo "TOPUP : subj $subj , sess $sess : merging diffs... "
      fsl_sub -l $logdir -N topup_fslmerge_$(subjsess) fslmerge -t $fldr/diffs_merged $(cat $fldr/diff.files | cut -d " " -f 1) >> $JIDfile
    done
  done
  
  waitIfBusy $JIDfile
  
  # perform eddy-correction, if applicable
  if [ $TOPUP_USE_EC -eq 1 ] ; then
    for subj in `cat $outdir/.subjects` ; do
      for sess in `cat $outdir/.sessions_struc` ; do
        fldr=$outdir
        
        # cleanup previous runs...
        rm -f $fldr/ec_diffs_merged_???_*.nii.gz # removing temporary files from prev. run
        if [ ! -z "$(ls $fldr/ec_diffs_merged_???.ecclog 2>/dev/null)" ] ; then    
          echo "TOPUP : subj $subj , sess $sess : WARNING : eddy_correct logfile(s) from a previous run detected - deleting..."
          rm $fldr/ec_diffs_merged_???.ecclog # (!)
        fi
        # eddy-correct each run...
        for i in `seq -f %03g 001 $(cat $fldr/diff.files | wc -l)` ; do # note: don't use seq -w (bash compatibility issues!) (!)
          dwifile=$(cat $fldr/diff.files | sed -n ${i}p | cut -d " " -f 1)
          bvalfile=$(cat $fldr/bval.files | sed -n ${i}p)
          
          # get B0 index          
          b0img=`getB0Index $bvalfile $fldr/ec_ref_${i}.idx | cut -d " " -f 1` ; min=`getB0Index $bvalfile $fldr/ec_ref_${i}.idx | cut -d " " -f 2` 
          
          # create a task file for fsl_sub, which is needed to avoid accumulations when SGE does a re-run on error
          echo "rm -f $fldr/ec_diffs_merged_${i}*.nii.gz ; \
                rm -f $fldr/ec_diffs_merged_${i}.ecclog ; \
                $scriptdir/eddy_correct.sh $dwifile $fldr/ec_diffs_merged_${i} $b0img $TOPUP_EC_DOF $TOPUP_EC_COST trilinear" > $fldr/topup_ec_${i}.cmd
          
          # eddy-correct
          echo "TOPUP : subj $subj , sess $sess : eddy_correction of '$dwifile' (ec_diffs_merged_${i}) is using volume no. $b0img as B0 (val:${min})..."
          fsl_sub -l $logdir -N topup_eddy_correct_$(subjsess) -t $fldr/topup_ec_${i}.cmd >> $JIDfile
        done        
      done
    done
    
    waitIfBusy $JIDfile    
    
    # plot ecclogs...
    for subj in `cat $outdir/.subjects` ; do
      for sess in `cat $outdir/.sessions_struc` ; do
        fldr=$outdir
        cd $fldr
        for i in `seq -f %03g 001 $(cat diff.files | wc -l)` ; do # note: don't use seq -w (bash compatibility issues!) (!)
          echo "TOPUP : subj $subj , sess $sess : plotting ec_diffs_merged_${i}.ecclog..."
          eddy_correct_plot ec_diffs_merged_${i}.ecclog $(subjsess)-${i}
          # horzcat
          pngappend ec_disp.png + ec_rot.png + ec_trans.png ec_${i}.png
          # accumulate
          if [ $i -gt 1 ] ; then
            pngappend ec_plot.png - ec_${i}.png ec_plot.png
          else
            cp ec_${i}.png ec_plot.png
          fi
          # cleanup
          rm  ec_disp.png ec_rot.png ec_trans.png ec_${i}.png
        done
        cd $sdir
      done
    done
      
  fi
fi

waitIfBusy $JIDfile

# TOPUP low-B images: create index and extract
if [ $TOPUP_STG2 -eq 1 ] ; then
  echo "----- BEGIN TOPUP_STG2 -----"
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
      
      if [ ! -f $fldr/$(subjsess)_acqparam.txt ] ; then echo "TOPUP : subj $subj , sess $sess : ERROR : parameter file $fldr/$(subjsess)_acqparam.txt not found - continuing loop..." ; continue ; fi
      
      # display info
      echo "TOPUP : subj $subj , sess $sess : concatenate bvals... "
      echo "`cat $fldr/bvals-_concat.txt`" "`cat $fldr/bvals+_concat.txt`" > $fldr/bvals_concat.txt
      paste -d " " $fldr/bvecs-_concat.txt $fldr/bvecs+_concat.txt > $fldr/bvecs_concat.txt
       
      # get B0 index
      min=`row2col $fldr/bvals_concat.txt | getMin` # find minimum value (usually representing the "B0" image)
      echo "TOPUP : subj $subj , sess $sess : minimum b-value in merged diff. is $min"
      b0idces=`getIdx $fldr/bvals_concat.txt $min`
      echo $b0idces | row2col > $fldr/lowb.idx
      
      # creating index file for topup (only low-B images)
      echo "TOPUP : subj $subj , sess $sess : creating index file for TOPUP (only low-B images)..."      
      rm -f $fldr/$(subjsess)_acqparam_lowb.txt ; rm -f $fldr/$(subjsess)_acqparam_lowb_inv.txt # clean-up previous runs...
      for b0idx in $b0idces ; do
        line=`echo "$b0idx + 1" | bc -l`
        cat $fldr/$(subjsess)_acqparam.txt | sed -n ${line}p >> $fldr/$(subjsess)_acqparam_lowb.txt
        cat $fldr/$(subjsess)_acqparam_inv.txt | sed -n ${line}p >> $fldr/$(subjsess)_acqparam_lowb_inv.txt
      done
          
      ## creating index file for topup (only the first low-B image in each dwi file)
      #echo "TOPUP : subj $subj , sess $sess : creating index file for TOPUP (only the first low-B image in each dwi-file)..." 
      #c=0 ; _nvol=0 ; nvol=0
      #rm -f $fldr/$(subjsess)_acqparam_lowb_1st.txt ; rm -f $fldr/$(subjsess)_acqparam_lowb_1st_inv.txt # clean-up previous runs...
      #for i in $(cat $fldr/bval.files) ; do
        #_min=`row2col $i | getMin`
        #_idx=`getIdx $i $_min` ;  _idx=$(echo $_idx | cut -d " " -f 1) ; _idx=$(echo "$_idx + 1" | bc -l)
        #if [ $c -gt 0 ] ; then
          #_nvol=$(cat $fldr/diff.files | sed -n ${c}p | cut -d ":" -f 2-) ;
        #fi
        #nvol=$(( $nvol + $_nvol ))
        #_line=$(echo "$nvol + $_idx" | bc -l)
        
        #cat $fldr/$(subjsess)_acqparam.txt | sed -n ${_line}p >> $fldr/$(subjsess)_acqparam_lowb_1st.txt
        #cat $fldr/$(subjsess)_acqparam_inv.txt | sed -n ${_line}p >> $fldr/$(subjsess)_acqparam_lowb_1st_inv.txt
        #c=$[$c+1]
      #done   
      
      # extract B0 images
      lowbs=""
      for b0idx in $b0idces ; do    
        echo "TOPUP : subj $subj , sess $sess : found B0 image in merged diff. at pos. $b0idx (val:${min}) - extracting..."
        lowb="$fldr/b${min}_`printf '%05i' $b0idx`"
        fsl_sub -l $logdir -N topup_fslroi_$(subjsess) fslroi $fldr/diffs_merged $lowb $b0idx 1  >> $JIDfile
        lowbs=$lowbs" "$lowb
      done
      
      # save filenames to text file
      echo "$lowbs" > $fldr/lowb.files; lowbs=""
      
      # wait here to prevent overload...
      waitIfBusy $JIDfile
    done
  done
fi

waitIfBusy $JIDfile

# TOPUP merge B0 images
if [ $TOPUP_STG3 -eq 1 ] ; then
  echo "----- BEGIN TOPUP_STG3 -----"
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
      
      if [ ! -f $fldr/$(subjsess)_acqparam.txt ] ; then echo "TOPUP : subj $subj , sess $sess : ERROR : parameter file $fldr/$(subjsess)_acqparam.txt not found - continuing loop..." ; continue ; fi
      
      # merge B0 images
      echo "TOPUP : subj $subj , sess $sess : merging low-B volumes..."
      fsl_sub -l $logdir -N topup_fslmerge_$(subjsess) fslmerge -t $fldr/$(subjsess)_lowb_merged $(cat $fldr/lowb.files) >> $JIDfile
      
    done
  done
fi

waitIfBusy $JIDfile

# TOPUP execute TOPUP
if [ $TOPUP_STG4 -eq 1 ] ; then
  echo "----- BEGIN TOPUP_STG4 -----"
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
      
      if [ ! -f $fldr/$(subjsess)_acqparam.txt ] ; then echo "TOPUP : subj $subj , sess $sess : ERROR : parameter file $fldr/$(subjsess)_acqparam.txt not found - continuing loop..." ; continue ; fi
      
      # execute TOPUP
      echo "TOPUP : subj $subj , sess $sess : executing TOPUP on merged low-B volumes..."
      mkdir -p $fldr/fm # dir. for fieldmap related stuff
      echo "topup -v --imain=$fldr/$(subjsess)_lowb_merged --datain=$fldr/$(subjsess)_acqparam_lowb.txt --config=b02b0.cnf --out=$fldr/$(subjsess)_field_lowb --fout=$fldr/fm/field_Hz_lowb --iout=$fldr/fm/uw_lowb_merged_chk ; \
      fslmaths $fldr/fm/field_Hz_lowb -mul 6.2832 $fldr/fm/fmap_rads" | tee $fldr/topup.cmd
      fsl_sub -l $logdir -N topup_topup_$(subjsess) -t $fldr/topup.cmd  >> $JIDfile
      #echo "fsl_sub -l $logdir -N topup_topup_$(subjsess) topup -v --imain=$fldr/$(subjsess)_lowb_merged --datain=$fldr/$(subjsess)_acqparam_lowb.txt --config=b02b0.cnf --out=$fldr/$(subjsess)_field_lowb --fout=$fldr/$(subjsess)_fieldHz_lowb --iout=$fldr/$(subjsess)_unwarped_lowb" > $fldr/topup.cmd
      #. $fldr/topup.cmd      
     
    done
  done
fi

waitIfBusy $JIDfile

# TOPUP apply warp
if [ $TOPUP_STG5 -eq 1 ] ; then
  echo "----- BEGIN TOPUP_STG5 -----"
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
      
      if [ ! -f $fldr/$(subjsess)_acqparam.txt ] ; then echo "TOPUP : subj $subj , sess $sess : ERROR : parameter file $fldr/$(subjsess)_acqparam.txt not found - continuing loop..." ; continue ; fi
      
      # for applywarp: get appropriate line in TOPUP index file (containing parameters pertaining to the B0 images) that refers to the first b0 volume in the respective DWI input file.
      line_b0=1 ; j=0 ; lines_b0p=""; lines_b0m=""
      for i in $(cat $fldr/bval-.files) ; do
        if [ $j -gt 0 ] ; then
          line_b0=$(echo "scale=0; $line_b0 + $nb0" | bc -l)
        fi
        min=`row2col $i | getMin`
        nb0=$(echo `getIdx $i $min` | wc -w)
        lines_b0m=$lines_b0m" "$line_b0
        j=$[$j+1]
      done      
      for i in $(cat $fldr/bval+.files) ; do
        line_b0=$(echo "scale=0; $line_b0 + $nb0" | bc -l)
        min=`row2col $i | getMin`
        nb0=$(echo `getIdx $i $min` | wc -w)
        lines_b0p=$lines_b0p" "$line_b0
      done
      j=""
      
      # generate commando without eddy-correction
      nplus=`ls $pttrn_diffsplus | wc -l`      
      rm -f $fldr/applytopup.cmd
      for i in `seq 1 $nplus` ; do
        j=`echo "$i + $nplus" | bc -l`

        blipdown=`ls $pttrn_diffsminus | sed -n ${i}p`
        blipup=`ls $pttrn_diffsplus | sed -n ${i}p`
        
        b0plus=$(echo $lines_b0p | cut -d " " -f $i)
        b0minus=$(echo $lines_b0m | cut -d " " -f $i)
        
        n=`printf %03i $i`
        imrm $fldr/${n}_topup_corr.* # delete prev. run
        echo "applytopup --imain=$blipdown,$blipup --datain=$fldr/$(subjsess)_acqparam_lowb.txt --inindex=${b0minus},${b0plus} --topup=$fldr/$(subjsess)_field_lowb --method=lsr --out=$fldr/${n}_topup_corr" >> $fldr/applytopup.cmd
        #echo "applytopup --imain=$blipdown,$blipup --datain=$fldr/$(subjsess)_acqparam_lowb_1st.txt --inindex=$i,$j --topup=$fldr/$(subjsess)_field_lowb --method=lsr --out=$fldr/${n}_topup_corr" >> $fldr/applytopup.cmd
      done
      
      # generate commando with eddy-correction
      nplus=`ls $pttrn_diffsplus | wc -l`      
      rm -f $fldr/applytopup_ec.cmd
      for i in `seq 1 $nplus` ; do
        j=`echo "$i + $nplus" | bc -l`
        
        blipdown=$fldr/ec_diffs_merged_$(printf %03i $i)
        blipup=$fldr/ec_diffs_merged_$(printf %03i $j)
        
        b0plus=$(echo $lines_b0p | cut -d " " -f $i)
        b0minus=$(echo $lines_b0m | cut -d " " -f $i)
        
        n=`printf %03i $i`
        imrm $fldr/${n}_topup_corr_ec.* # delete prev. run
        echo "applytopup --imain=$blipdown,$blipup --datain=$fldr/$(subjsess)_acqparam_lowb.txt --inindex=${b0minus},${b0plus} --topup=$fldr/$(subjsess)_field_lowb --method=lsr --out=$fldr/${n}_topup_corr_ec" >> $fldr/applytopup_ec.cmd
        #echo "applytopup --imain=$blipdown,$blipup --datain=$fldr/$(subjsess)_acqparam_lowb_1st.txt --inindex=$i,$j --topup=$fldr/$(subjsess)_field_lowb --method=lsr --out=$fldr/${n}_topup_corr_ec" >> $fldr/applytopup_ec.cmd
      done
      
      # generate commando with EDDY
      echo "$scriptdir/eddy_topup.sh $fldr $fldr/$(subjsess)_topup_corr_eddy_merged.nii.gz" > $fldr/eddy.cmd

    done
  done  

  # execute...
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
  
      if [ $TOPUP_USE_NATIVE -eq 1 ] ; then
        echo "TOPUP : subj $subj , sess $sess : applying warps to native DWIs..."
        cat $fldr/applytopup.cmd
        fsl_sub -l $logdir -N topup_applytopup_$(subjsess) -t $fldr/applytopup.cmd >> $JIDfile
      fi
      if [ $TOPUP_USE_EC -eq 1 ] ; then
        echo "TOPUP : subj $subj , sess $sess : applying warps to eddy-corrected DWIs..."
        cat $fldr/applytopup_ec.cmd
        fsl_sub -l $logdir -N topup_applytopup_ec_$(subjsess) -t $fldr/applytopup_ec.cmd >> $JIDfile
      fi    
      if [ $TOPUP_USE_EDDY -eq 1 ] ; then
        echo "TOPUP : subj $subj , sess $sess : executing EDDY..."
        fsl_sub -l $logdir -N topup_eddy_$(subjsess) -t $fldr/eddy.cmd >> $JIDfile
      fi  
       
    done
  done
       
  waitIfBusy $JIDfile
      
  # merge corrected files and remove negative values
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
      
      # merge corrected files
      if [ $TOPUP_USE_NATIVE -eq 1 ] ; then
        echo "TOPUP : subj $subj , sess $sess : merging topup-corrected DWIs..."
        #fsl_sub -l $logdir -N topup_merge_corr_$(subjsess) fslmerge -t $fldr/$(subjsess)_topup_corr_merged $(imglob $fldr/*_topup_corr.nii.gz)
        fslmerge -t $fldr/$(subjsess)_topup_corr_merged $(imglob $fldr/*_topup_corr.nii.gz)
      fi
      if [ $TOPUP_USE_EC -eq 1 ] ; then
        echo "TOPUP : subj $subj , sess $sess : merging topup-corrected & eddy-corrected DWIs..."
        #fsl_sub -l $logdir -N topup_merge_corr_ec_$(subjsess) fslmerge -t $fldr/$(subjsess)_topup_corr_ec_merged $(imglob $fldr/*_topup_corr_ec.nii.gz)
        fslmerge -t $fldr/$(subjsess)_topup_corr_ec_merged $(imglob $fldr/*_topup_corr_ec.nii.gz)
      fi      
 
    done
  done
  
  waitIfBusy $JIDfile
  
  # remove negative values
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
      
      echo "TOPUP : subj $subj , sess $sess : zeroing negative values in topup-corrected DWIs..."
      if [ $TOPUP_USE_NATIVE -eq 1 -a -f $fldr/$(subjsess)_topup_corr_merged.nii.gz ] ; then fsl_sub -l $logdir -N topup_noneg_$(subjsess) fslmaths $fldr/$(subjsess)_topup_corr_merged -thr 0 $fldr/$(subjsess)_topup_corr_merged >> $JIDfile ; fi
      if [ $TOPUP_USE_EC -eq 1 -a -f $fldr/$(subjsess)_topup_corr_ec_merged.nii.gz ] ; then fsl_sub -l $logdir -N topup_noneg_ec_$(subjsess) fslmaths $fldr/$(subjsess)_topup_corr_ec_merged -thr 0 $fldr/$(subjsess)_topup_corr_ec_merged >> $JIDfile ; fi
      # eddy script already removed neg. values
      #if [ -f $fldr/$(subjsess)_topup_corr_eddy_merged.nii.gz ] ; then fsl_sub -l $logdir -N topup_noneg_eddy_$(subjsess) fslmaths $fldr/$(subjsess)_topup_corr_eddy_merged -thr 0 $fldr/$(subjsess)_topup_corr_eddy_merged >> $JIDfile ; fi
    done
  done
  
  waitIfBusy $JIDfile
  
  # create masked fieldmap
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
      
      echo "TOPUP : subj $subj , sess $sess : masking topup-derived fieldmap..."
      if [ ! -f $fldr/fm/fmap_rads.nii.gz ] ; then  echo "TOPUP : subj $subj , sess $sess : ERROR : fieldmap not found in '$fldr/fm/' - exiting..." ; exit 1 ; fi
      if [ $TOPUP_USE_NATIVE -eq 1 ] ; then corrfile=$fldr/$(subjsess)_topup_corr_merged.nii.gz ; fi
      if [ $TOPUP_USE_EC -eq 1 ] ; then corrfile=$fldr/$(subjsess)_topup_corr_ec_merged.nii.gz ; fi ;
      if [ $TOPUP_USE_EDDY -eq 1 ] ; then corrfile=$fldr/$(subjsess)_topup_corr_eddy_merged.nii.gz ; fi ;
      #min=`row2col $fldr/bvals_concat.txt | getMin`
      #b0idces=`getIdx $fldr/bvals-_concat.txt $min` 
      #lowbs=""
      #for b0idx in $b0idces ; do 
        #lowb="$fldr/fm/uw_b${min}_`printf '%05i' $b0idx`"
        #echo "    found B0 image in merged diff. at pos. $b0idx (val:${min}) - extracting from '$corrfile'..."
        #fslroi $corrfile $lowb $b0idx 1
        #lowbs=$lowbs" "$lowb
      #done
      lowbs=""; nvols=0; b0idx=0
      for f in $(cat $fldr/bval-.files) ; do
        min=$(cat $f | row2col | getMin); idx=$(findIndex $f $min)
        b0idx=$[$b0idx+$nvols+$idx]
        echo "    found B0 image in merged diff. at pos. $b0idx (val:${min}) - extracting from '$corrfile':"
        lowb="$fldr/fm/uw_b${min}_`printf '%05i' $b0idx`"
        cmd="fslroi $corrfile $lowb $b0idx 1"
        echo "      $cmd"
        $cmd
        lowbs=$lowbs" "$lowb
        nvols=$(cat $f | row2col | wc -l)
      done ; nvols="" ; b0idx=""      
      echo "    creating mask..."
      fithres=0.2 # (!)
      echo "fslmerge -t $fldr/fm/uw_lowb_merged $lowbs ; \
      fslmaths $fldr/fm/uw_lowb_merged -Tmean $fldr/fm/uw_lowb_mean ; \
      bet $fldr/fm/uw_lowb_mean $fldr/fm/uw_lowb_mean_brain_${fithres} -f $fithres -m ; \
      fslmaths $fldr/fm/fmap_rads -mas $fldr/fm/uw_lowb_mean_brain_${fithres}_mask $fldr/fm/fmap_rads_masked" > $fldr/topup_b0mask.cmd
      fsl_sub -l $logdir -N topup_b0mask_$(subjsess) -t $fldr/topup_b0mask.cmd >> $JIDfile
      
      # link to mask
      echo "TOPUP : subj $subj , sess $sess : link to unwarped mask..."
      ln -sfv ./fm/uw_lowb_mean_brain_${fithres}.nii.gz $fldr/uw_nodif_brain.nii.gz
      ln -sfv ./fm/uw_lowb_mean_brain_${fithres}_mask.nii.gz $fldr/uw_nodif_brain_mask.nii.gz
      # link to mean brain
      ln -sfv ./uw_lowb_mean_brain_${fithres}.nii.gz $fldr/fm/uw_lowb_mean_brain.nii.gz
      ln -sfv ./uw_lowb_mean_brain_${fithres}_mask.nii.gz $fldr/fm/uw_lowb_mean_brain_mask.nii.gz
      
    done
  done    
fi

waitIfBusy $JIDfile

# TOPUP estimate tensor model
if [ $TOPUP_STG6 -eq 1 ] ; then
  echo "----- BEGIN TOPUP_STG6 -----"
  for subj in `cat $outdir/.subjects` ; do
    for sess in `cat $outdir/.sessions_struc` ; do
      fldr=$outdir
      
      # averaging +/- bvecs & bvals...
      # NOTE: bvecs are averaged further below (following rotation)
      average $fldr/bvals-_concat.txt $fldr/bvals+_concat.txt > $fldr/avg_bvals.txt
      average $fldr/bvecs-_concat.txt $fldr/bvecs+_concat.txt > $fldr/avg_bvecs.txt # for EDDY no rotations are applied
      
      # rotate bvecs to compensate for eddy-correction, if applicable
      if [ $TOPUP_USE_EC -eq 1 ] ; then
        if [ -z "$(ls $fldr/ec_diffs_merged_???.ecclog 2>/dev/null)" ] ; then 
          echo "TOPUP : subj $subj , sess $sess : ERROR : *.ecclog file(s) not found, but needed to rotate b-vectors -> skipping this part..." 
        
        else 
          for i in `seq -f %03g 001 $(cat $fldr/diff.files | wc -l)` ; do
            bvecfile=`sed -n ${i}p $fldr/bvec.files`
            echo "TOPUP : subj $subj , sess $sess : rotating '$bvecfile' according to 'ec_diffs_merged_${i}.ecclog'"
            xfmrot $fldr/ec_diffs_merged_${i}.ecclog $bvecfile $fldr/bvecs_ec_${i}.rot
          done
        fi
      fi
      
      # rotate bvecs: get appropriate line in TOPUP index file (containing parameters pertaining to the B0 images) that refers to the first b0 volume in the respective DWI input file.
      line_b0=1 ; j=0 ; lines_b0p=""; lines_b0m=""
      for i in $(cat $fldr/bval-.files) ; do
        if [ $j -gt 0 ] ; then
          line_b0=$(echo "scale=0; $line_b0 + $nb0" | bc -l)
        fi
        min=`row2col $i | getMin`
        nb0=$(echo `getIdx $i $min` | wc -w)
        lines_b0m=$lines_b0m" "$line_b0
        j=$[$j+1]
      done      
      for i in $(cat $fldr/bval+.files) ; do
        line_b0=$(echo "scale=0; $line_b0 + $nb0" | bc -l)
        min=`row2col $i | getMin`
        nb0=$(echo `getIdx $i $min` | wc -w)
        lines_b0p=$lines_b0p" "$line_b0
      done
      j="" ; lines_b0=$lines_b0m" "$lines_b0p
            
      # rotate bvecs to compensate for TOPUP 6 parameter rigid-body correction using OCTAVE (for each run)
      for i in `seq -f %03g 001 $(cat $fldr/diff.files | wc -l)` ; do # for each run do...        
        # copy OCTAVE template
        cp $tmpltdir/template_makeXfmMatrix.m $fldr/makeXfmMatrix_${i}.m
        
        # define vars           
        line_b0=$(echo $lines_b0 | cut -d " " -f $i)
        rots=`sed -n ${line_b0}p $fldr/$(subjsess)_field_lowb_movpar.txt | awk '{print $4"  "$5"  "$6}'` # cut -d " " -f 7-11` # last three entries are rotations in radians
        nscans=`sed -n ${i}p $fldr/diff.files | cut -d : -f 2` # number of scans in run
        fname_mat=topup_diffs_merged_${i}.mat # filename with n 4x4 affine matrices
        
        # do run-specific substitutions in OCTAVE template
        sed -i "s|function M = .*|function M = makeXfmMatrix_${i}|g" $fldr/makeXfmMatrix_${i}.m
        sed -i "s|R=.*|R=[$rots]|g" $fldr/makeXfmMatrix_${i}.m
        sed -i "s|repeat=.*|repeat=$nscans|g" $fldr/makeXfmMatrix_${i}.m
        sed -i "s|filename=.*|filename='$fname_mat'|g" $fldr/makeXfmMatrix_${i}.m
        
        # change directory and unset error flag because of strange OCTAVE behavior and unclear error 'error: matrix cannot be indexed with .' - but seems to work anyhow
        cd $fldr
          set +e # unset exit on error bc. octave always throws an error (?)
          echo "TOPUP : subj $subj , sess $sess : create rotation matrices '$(basename $fname_mat)' ($nscans entries) for 6-parameter TOPUP motion correction (angles: $rots)..."
          echo "NOTE: Octave may throw an error here for reasons unknown."
          octave -q --eval makeXfmMatrix_${i}.m >& /dev/null
          set -e
        cd $sdir
        
        # check the created rotation matrix
        head -n8 $fldr/$fname_mat > $fldr/check.mat
        echo "TOPUP : subj $subj , sess $sess : CHECK rotation angles - topup input: $(printf ' %0.6f' $rots)"
        echo "TOPUP : subj $subj , sess $sess : CHECK rotation angles - avscale out: $(avscale --allparams $fldr/check.mat | grep "Rotation Angles" | cut -d '=' -f2)"
        rm $fldr/check.mat
        
        # apply the rotation matrix to b-vector file
        if [ $TOPUP_USE_NATIVE -eq 1 ] ; then 
          bvecfile=`sed -n ${i}p $fldr/bvec.files`
          echo "TOPUP : subj $subj , sess $sess : apply rotation matrices '$(basename $fname_mat)' to '`basename $bvecfile`' -> 'bvecs_topup_${i}.rot'"
          xfmrot $fldr/$fname_mat $bvecfile $fldr/bvecs_topup_${i}.rot
        fi        
        if [ $TOPUP_USE_EC -eq 1 ] ; then
          bvecfile=$fldr/bvecs_ec_${i}.rot
          echo "TOPUP : subj $subj , sess $sess : apply rotation matrices '$(basename $fname_mat)' to '`basename $bvecfile`' -> 'bvecs_topup_ec_${i}.rot'"
          xfmrot $fldr/$fname_mat $bvecfile $fldr/bvecs_topup_ec_${i}.rot
        fi
      done
      
      # average rotated bvecs
      nplus=`cat $fldr/bvec+.files | wc -l`
      for i in `seq -f %03g 001 $nplus` ; do
        j=`echo "$i + $nplus" | bc -l` ; j=`printf %03i $j`
        if [ $TOPUP_USE_NATIVE -eq 1 ] ; then 
          echo "TOPUP : subj $subj , sess $sess : averaging rotated blip+/blip- b-vectors (no eddy-correction)..."
          average $fldr/bvecs_topup_${i}.rot $fldr/bvecs_topup_${j}.rot > $fldr/avg_bvecs_topup_${i}.rot
        fi
        if [ $TOPUP_USE_EC -eq 1 ] ; then
          echo "TOPUP : subj $subj , sess $sess : averaging rotated blip+/blip- b-vectors (incl. eddy-correction)..."
          average $fldr/bvecs_topup_ec_${i}.rot $fldr/bvecs_topup_ec_${j}.rot > $fldr/avg_bvecs_topup_ec_${i}.rot
        fi
      done
      
      # concatenate averaged and rotated bvecs
      if [ $TOPUP_USE_NATIVE -eq 1 ] ; then      
       echo "TOPUP : subj $subj , sess $sess : concatenate averaged and rotated b-vectors (no eddy-correction)..."
       concat_bvecs "$fldr/avg_bvecs_topup_???.rot" $fldr/avg_bvecs_topup.rot
      fi      
      if [ $TOPUP_USE_EC -eq 1 ] ; then
        echo "TOPUP : subj $subj , sess $sess : concatenate averaged and rotated b-vectors (incl. eddy-correction)..."
        concat_bvecs "$fldr/avg_bvecs_topup_ec_???.rot" $fldr/avg_bvecs_topup_ec.rot
      fi          
        
      # display info
      echo "TOPUP : subj $subj , sess $sess : dtifit is estimating tensor model..."
      
      # estimate tensor model (rotated bvecs)
      if [ $TOPUP_USE_NATIVE -eq 1 ] ; then           
        echo "TOPUP : subj $subj , sess $sess : dtifit is estimating tensor model with rotated b-vectors (no eddy-correction)..."
        fsl_sub -l $logdir -N topup_dtifit_noec_bvecrot_$(subjsess) dtifit -k $fldr/$(subjsess)_topup_corr_merged -m $fldr/uw_nodif_brain_mask -r $fldr/avg_bvecs_topup.rot -b $fldr/avg_bvals.txt  -o $fldr/$(subjsess)_dti_topup_noec_bvecrot >> $JIDfile
      fi
      if [ $TOPUP_USE_EC -eq 1 ] ; then
        echo "TOPUP : subj $subj , sess $sess : dtifit is estimating tensor model with rotated b-vectors (incl. eddy-correction)..."
        fsl_sub -l $logdir -N topup_dtifit_ec_bvecrot_$(subjsess) dtifit -k $fldr/$(subjsess)_topup_corr_ec_merged -m $fldr/uw_nodif_brain_mask -r $fldr/avg_bvecs_topup_ec.rot  -b $fldr/avg_bvals.txt  -o $fldr/$(subjsess)_dti_topup_ec_bvecrot >> $JIDfile
      fi
      if [ $TOPUP_USE_EDDY -eq 1 ] ; then
        echo "TOPUP : subj $subj , sess $sess : dtifit is estimating tensor model w/o rotated b-vectors (incl. EDDY-correction)..."
        fsl_sub -l $logdir -N topup_dtifit_eddy_norot_$(subjsess) dtifit -k $fldr/$(subjsess)_topup_corr_eddy_merged -m $fldr/uw_nodif_brain_mask -r $fldr/avg_bvecs.txt  -b $fldr/avg_bvals.txt  -o $fldr/$(subjsess)_dti_topup_eddy_norot >> $JIDfile
      fi
    done
  done
fi

waitIfBusy $JIDfile

#######################
# ----- END TOPUP -----
#######################

echo "" 
echo "`basename $0`: done."
