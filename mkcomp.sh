#!/bin/bash

###############################################################
#
# Este script foi feito para ser executado por usuarios
# normais atraves do sudo. Para habilitar os usuarios a
# executarem este script, deve-se, como root, executar o
# comando visudo e adicionar a seguinte linha
#
# %cc_users       ALL=(root)      NOPASSWD: /tmp/mkcomp.sh
#
# %cc_users eh um exemplo de grupo de usuarios que terao
# permissao para executar este script
# /tmp/mkcomp.sh eh o path completo deste script. Este
# script deve ser sempre invocado pelo path completo.
#############################################################

CT_CMD=/opt/rational/clearcase/bin/cleartool
MY_PVOB=/home0/pvob/bi_pvob
VOB_GROUP=rgcs
VOB_GROUPS_REMOVE=bin
MKCOMP_VIEW=mkcomp_view
CC_PASSWD=alstom
VOB_STGLOC=-auto
VIEW_STGLOC=-auto

### captura o usuario que chamou este script
ORIGINAL_USER=$SUDO_USER

### funcao para criar a VOB se nao existir
function cria_vob {

  ### cria uma vob publica no storage location default  
  su -c "$CT_CMD mkvob -nc -tag $myvob -public \
    -password $CC_PASSWD -stgloc $VOB_STGLOC" $ORIGINAL_USER

  ### se a variavel estiver definida, remover esses grupos da VOB
  if [[ "$VOB_GROUPS_REMOVE" != "" ]]; then 
    _VOBSTG=`$CT_CMD lsvob $myvob | perl -pi -e 's/^.?\s([^\s]+)\s+([^\s]+)\s+([^\s]+).*$/$2/g'`
    $CT_CMD protectvob -force -del $VOB_GROUPS_REMOVE $_VOBSTG
  fi
}

function cria_vob_options {
  read -p "A VOB \"$myvob\" nao existe, deseja cria-la? (S/N) " criavob
  case "$criavob" in
    S|s) cria_vob;;
    N|n) exit;;
    *) echo "Por favor responda sim (s) ou nao (n)."; cria_vob_options;
  esac
}

### opcionalmente, aceita nome da VOB e nome do componente como parametros
### na linha de comando
myvob=$1
mycomp=$2

### pede o nome da VOB e do componente se estes nao forem passados na
### linha de comando
if [ $# -ne 2 ]; then
  read -p "Digite o nome da VOB (vob tag): " myvob
  read -p "Digite o nome do componente: " mycomp
fi

### verifica se a VOB ja existe
$CT_CMD lsvob -s $myvob > /dev/null 2>&1
RC=$?

### cria a VOB se nao existir
if [[ $RC -ne 0 ]]; then
  cria_vob_options
fi

### verifica se a view existe
$CT_CMD lsview -s $MKCOMP_VIEW > /dev/null 2>&1
RC=$?

### cria a view se nao existir
if [[ $RC -ne 0 ]]; then
  $CT_CMD mkview -tag $MKCOMP_VIEW -stgloc $VIEW_STGLOC
fi

### inicia a view se nao estiver iniciada
if [ ! -d "/view/$MKCOMP_VIEW" ]; then $CT_CMD startview $MKCOMP_VIEW; fi

### verifica se a VOB esta montada
$CT_CMD lsvob $myvob | grep \* > /dev/null 2>&1
RC=$?

### monta a VOB se nao estiver montada
if [[ $RC -ne 0 ]]; then
  $CT_CMD mount $myvob
fi

VOBDIR="/view/$MKCOMP_VIEW/$myvob"

### cria o componente dentro do contexto de uma view (comando setview)
sg $VOB_GROUP "$CT_CMD setview -exec \
  \"$CT_CMD mkcomp -root $VOBDIR/$mycomp $mycomp@$MY_PVOB\" $MKCOMP_VIEW" 

### altera o owner do componente para o usuario que chamou este script
$CT_CMD protect -chown $ORIGINAL_USER -chgrp $VOB_GROUP component:$mycomp@$MY_PVOB
