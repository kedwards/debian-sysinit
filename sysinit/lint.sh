#!/usr/bin/env bash

set -e

opts=':hd:p:'

script_name=${0##*/}
script_dir="$( cd "$( dirname "$0" )" && pwd )"
script_path=${script_dir}/${script_name}
cf_template_dir="${script_dir}/cfn_templates/*.yml"

usage() {
  echo ""
  echo ""
  echo "Usage: ${script_name} options"
  echo ""
  echo "options:"
  echo "  -d | cf template directory"
  echo "  -h | print this help menu"
  echo "  -p | AWS profile"
  echo ""
  exit 1
}

while getopts ${opts} opt
do
  case "$opt" in
    d)  cf_template_dir=${OPTARG}
        ;;
    h)  usage
        ;;
    p)  aws_profile=--profile=${OPTARG}
        ;;
    \?)
        usage
        ;;
  esac
done
shift $(($OPTIND - 1))

[[ -z "${AWS_PROFILE}" ]]

echo Linting..
for filename in ${cf_template_dir}; do
  echo "  - $filename"
  cfn-format -w ${filename}
  cfn-lint -t ${filename} -i W1020 W2030;
  aws ${aws_profile} cloudformation validate-template --template-body file://${filename};
done