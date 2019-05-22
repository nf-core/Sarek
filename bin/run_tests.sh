#!/bin/bash
set -xeuo pipefail

CPUS=2
LOGS=''
PROFILE=docker
TEST=ALL
TRAVIS_BUILD_DIR=${TRAVIS_BUILD_DIR:-.}
TRAVIS=${TRAVIS:-false}
VERBOSE=''

while [[ $# -gt 0 ]]
do
  key=$1
  case $key in
    -c|--cpus)
    CPUS=$2
    shift # past value
    ;;
    -n|--no-logs)
    LOGS=true
    shift # past value
    ;;
    -p|--profile)
    PROFILE=$2
    shift # past argument
    shift # past value
    ;;
    -t|--test)
    TEST=$2
    shift # past argument
    shift # past value
    ;;
    -v|--verbose)
    VERBOSE="-ansi-log false -dump-channels"
    shift # past value
    ;;
    *) # unknown option
    shift # past argument
    ;;
  esac
done

function manage_logs() {
  if [[ $LOGS ]]
  then
    rm -rf .nextflow* results/ work/
  fi
}

function run_sarek() {
  nextflow run ${TRAVIS_BUILD_DIR}/main.nf -profile test,${PROFILE} ${VERBOSE} --monochrome_logs $@
}

if [[ ALL,GERMLINE =~ $TEST ]]
then
  rm -rf data
  git clone --single-branch --branch sarek https://github.com/nf-core/test-datasets.git data
  run_sarek --tools=false --sample data/testdata/tiny/normal --noReports
  run_sarek --tools=false --sample results/Preprocessing/TSV/duplicateMarked.tsv --step recalibrate --noReports
  run_sarek --tools HaplotypeCaller,Strelka --sample results/Preprocessing/TSV/recalibrated.tsv --step variantCalling --noReports
  rm -rf data/
  manage_logs
fi

if [[ ALL,SOMATIC =~ $TEST ]]
then
  run_sarek --tools FreeBayes,HaplotypeCaller,Manta,Strelka,Mutect2 --noReports
  manage_logs
fi

if [[ ALL,TARGETED =~ $TEST ]]
then
  run_sarek --tools FreeBayes,HaplotypeCaller,Manta,Strelka,Mutect2 --noReports --targetBED https://github.com/nf-core/test-datasets/raw/sarek/testdata/target.bed
  manage_logs
fi

if [[ ALL,ANNOTATEALL,ANNOTATESNPEFF,ANNOTATEVEP =~ $TEST ]]
then
  if [[ $TEST = ANNOTATESNPEFF ]]
  then
    ANNOTATOR=snpEFF
  elif [[ $TEST = ANNOTATEVEP ]]
  then
    ANNOTATOR=VEP
  elif [[ ALL,ANNOTATEALL =~ $TEST ]]
  then
    ANNOTATOR=merge,snpEFF,VEP
  fi
  run_sarek --step annotate --tools ${ANNOTATOR} --sample https://github.com/nf-core/test-datasets/raw/sarek/testdata/vcf/Strelka_1234N_variants.vcf.gz --noReports
  manage_logs
fi

if [[ MULTIPLE =~ $TEST ]]
then
  run_sarek --sample https://github.com/nf-core/test-datasets/raw/sarek/testdata/tsv/tiny-multiple-https.tsv --tools FreeBayes,HaplotypeCaller,Manta,Strelka,Mutect2 --noReports
  manage_logs
fi
