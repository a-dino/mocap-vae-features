#!/bin/bash

#PBS -q gpu@pbs-m1.metacentrum.cz
#PBS -l walltime=24:0:0
#PBS -l select=1:ncpus=2:ngpus=1:mem=16gb:gpu_mem=8gb:scratch_local=50gb:cuda_version=13.0


#This script uses conda eviroment available on metacentrum.cz
#TODO: edit this path to the location of the repository
REPO_DIR='/storage/brno2/home/abecvarov/experiments'
ENV_NAME='cuda4'

#Select parameters
DIM=256
BETA=1
ITER=0
PART="hdm05"


# to run the clustering, you also need to install java
# JDK_PATH="/storage/brno12-cerit/home/user/jdk-21.0.7/bin/java"
JDK_PATH="/storage/brno12-cerit/home/drking/jdk-21.0.7/bin/java"

module add conda-modules
module add mambaforge

cd "${REPO_DIR}" || {
    echo >&2 "Repository directory ${REPO_DIR} does not exist!"
    exit 1
}

# every user on metacentrum should have access to this env
conda activate "/storage/brno2/home/abecvarov/envs/${ENV_NAME}" || {
    echo >&2 "Conda environment does not exist!"
    exit 2
}



python ${REPO_DIR}/mocap-vae-features/train.py --multirun exp=hdm05/all \
    latent_dim=${DIM} beta=${BETA} iteration=${ITER} body_model=${PART} > /dev/null 2>&1

#python ${REPO_DIR}/mocap-vae-features/train.py --multirun exp=pku-mmd/cs \
#    latent_dim=${DIM} beta=${BETA} iteration=${ITER} body_model=pku-mmd \
#    train_split=${REPO_DIR}/mocap-vae-features/pipelines/splits/CS_train_objects_messif-lines.txt /dev/null 2>&1

#python ${REPO_DIR}/mocap-vae-features/train.py --multirun exp=pku-mmd/cv \
#    latent_dim=${DIM} beta=${BETA} iteration=${ITER} body_model=pku-mmd \
#    train_split=${REPO_DIR}/mocap-vae-features/pipelines/splits/CV_train_objects_messif-lines.txt /dev/null 2>&1


wait

conda deactivate

echo "evaluation start"

[ -f "${REPO_DIR}/SCL/hdm05/all/model=hdm05_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data.gz" ] && gunzip -k "${REPO_DIR}/SCL/hdm05/all/model=hdm05_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data.gz"
#[ -f "${REPO_DIR}/SCL/pku-mmd/cs/model=pku-mmd_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data.gz" ] && gunzip -k "${REPO_DIR}/SCL/pku-mmd/cs/model=pku-mmd_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data.gz"
#[ -f "${REPO_DIR}/SCL/pku-mmd/cv/model=pku-mmd_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data.gz" ] && gunzip -k "${REPO_DIR}/SCL/pku-mmd/cv/model=pku-mmd_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data.gz"


COMMAND="${JDK_PATH} -jar ${REPO_DIR}/mocap-vae-features/evaluator.jar \
-fp ${REPO_DIR}/SCL/hdm05/all/model=hdm05_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data \
-k 4 \
--scl \
-dd ${REPO_DIR}/mocap-vae-features/pipelines/data/category_description.txt \
"
# -jar vyhodnocovaci program
# -fp path ku suboru na vyhodnotenie
# -k = pocet k nearest neighbours
# --scl je funkcia na hodnotenie (pomocou dynamic time warp + cosine distance)=========================
# -dd
# -help na evaluator.jar

mkdir -p "${REPO_DIR}/results/scl/hdm05/all/lat_dim=${DIM}_beta=${BETA}"
eval "${COMMAND}" >> "${REPO_DIR}/results/scl/hdm05/all/lat_dim=${DIM}_beta=${BETA}/results.txt"

COMMAND="${JDK_PATH} -jar ${REPO_DIR}/mocap-vae-features/evaluator.jar \
-fp ${REPO_DIR}/SCL/hdm05/all/model=hdm05_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data \
--scl \
-dd ${REPO_DIR}/mocap-vae-features/pipelines/pipelines/hdm05/category_description.txt \
"

# -dd ${REPO_DIR}/mocap-vae-features/pipelines/data/category_description.txt \

eval "${COMMAND}" >> "${REPO_DIR}/results/scl/hdm05/all/lat_dim=${DIM}_beta=${BETA}/results.txt"

# # ----------------------------------------------------------------------------------------

#COMMAND="${JDK_PATH} -jar ${REPO_DIR}/mocap-vae-features/evaluator.jar \
#-fp ${REPO_DIR}/SCL/pku-mmd/cv/model=pku-mmd_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data \
#-cv \
#-k 18 \
#--scl \
#-dd ${REPO_DIR}/mocap-vae-features/pipelines/description/pku-mmd/category_description.txt \
#"
#echo "${COMMAND}"
#mkdir -p "${REPO_DIR}/results/scl/pku-mmd/cv/lat_dim=${DIM}_beta=${BETA}"
#eval "${COMMAND}" >> "${REPO_DIR}/results/scl/pku-mmd/cv/lat_dim=${DIM}_beta=${BETA}/results-${ITER}.txt"
#
#COMMAND="${JDK_PATH} -jar ${REPO_DIR}/mocap-vae-features/evaluator.jar \
#-fp ${REPO_DIR}/SCL/pku-mmd/cv/model=pku-mmd_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data \
#-cv \
#--scl \
#-dd ${REPO_DIR}/mocap-vae-features/pipelines/description/pku-mmd/category_description.txt \
#"
#echo "${COMMAND}"
#eval "${COMMAND}" >> "${REPO_DIR}/results/scl/pku-mmd/cv/lat_dim=${DIM}_beta=${BETA}/results-${ITER}.txt"

## # ----------------------------------------------------------------------------------------
#
#COMMAND="${JDK_PATH} -jar ${REPO_DIR}/mocap-vae-features/evaluator.jar \
#-fp ${REPO_DIR}/SCL/pku-mmd/cs/model=pku-mmd_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data \
#-cs \
#-k 18 \
#--scl \
#-dd ${REPO_DIR}/mocap-vae-features/pipelines/description/pku-mmd/category_description.txt \
#"
#echo "${COMMAND}"
#mkdir -p "${REPO_DIR}/results/scl/pku-mmd/cs/lat_dim=${DIM}_beta=${BETA}"
#eval "${COMMAND}" >> "${REPO_DIR}/results/scl/pku-mmd/cs/lat_dim=${DIM}_beta=${BETA}/results-${ITER}.txt"
#
#COMMAND="${JDK_PATH} -jar ${REPO_DIR}/mocap-vae-features/evaluator.jar \
#-fp ${REPO_DIR}/SCL/pku-mmd/cs/model=pku-mmd_lat-dim=${DIM}_beta=${BETA}/${ITER}/predictions_full.data \
#-cs \
#--scl \
#-dd ${REPO_DIR}/mocap-vae-features/pipelines/description/pku-mmd/category_description.txt \
#"
#echo "${COMMAND}"
#eval "${COMMAND}" >> "${REPO_DIR}/results/scl/pku-mmd/cs/lat_dim=${DIM}_beta=${BETA}/results-${ITER}.txt"


echo "We are done!"