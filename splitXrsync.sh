#!/bin/bash
#Autor: @joseccnet

#Configuraciones Obligatorias:
remotesshaccount="" #Coloque su configuracion para acceso por ssh al servidor remoto. Ejem: userbob@192.168.1.5 , o tambien: userbob@myowndomain.xyz.com
remotedir="~/myremotedir" #Ejem: ~/myremotedir , o tambien /home/userbob/myremotedir . ESTE DIRECTORIO ES EL QUE SE SINCRONIZARA hacia el directorio local 'localdir'
localdir="~/mylocaldir" #Ejem: ~/mylocaldir , o tambien: /home/userjhon/mylocaldir

#Configuraciones opcionales:
numprocesos=4 #numero de procesos o hilos concurrentes para sincronizar con rsync.
sizesplitfile="30M" #Tamano de pedazo de rchivo en Megabytes. Ejem: 50M , 512M , 1024M , etc.
bwlimit="--bwlimit=1024" #Limite en Kbps, por proceso.
optsrsync1="$bwlimit -azPhc --partial-dir=$localdir/tmprsync --progress"
optsrsync2="--remove-source-files" #**ATENCION!!!** Eliminará los archivos remotos. Opcion predeterminada.

if [ "$localdir" == "" -o "$remotedir" == "" -o "$remotesshaccount" == "" ] ; then
   echo -e "\nEdite el script y configure almenos las siguientes variables: remotesshaccount , remotedir y localdir"
   echo "Nota: No olvide configurar 'ssh key authentication'. Referencia: https://www.google.com/#q=ssh%20key%20authentication"
   exit -1
fi

remotedirscaped="$(echo $remotedir | sed -e 's/\//\\\//g' -e 's/\./\\\./g')" #'Escapar caracteres especiales.'
function myrsync(){
   green='\033[0;32m'
   red='\033[0;31m'
   yellow='\033[1;33m'
   blue='\033[0;34m'
   NC='\033[0m' # No Color
   echo -e "${yellow}+${NC}$1${yellow}+${NC}" && rsync $optsrsync1 $remotesshaccount:$remotedir/$1 $localdir/$1 && echo -e "${blue}++${NC}$1${blue}++${NC}" && rsync $optsrsync1 $optsrsync2 $remotesshaccount:$remotedir/$1 $localdir/$1 && echo -e "+++${red}$1${NC}+++ ${green}Done!${NC}"
   [ "$?" != "0" ] && exit -1

   #Junta los pedazos de archivos:
   if [[ "$1" == *[0-9][0-9][0-9][0-9]z ]] ; then
      outputfile=$(echo $1 | sed 's/\.[0-9][0-9][0-9][0-9]z//g')
      cd $localdir
      touch $outputfile
      while true
      do
         ls .$outputfile.* > /dev/null 2>&1
         if [ $? == "0" ] ; then
            sleep 5
            continue
         fi
         break
      done
      if [ -f $outputfile\.[0-9][0-9][0-9][0-9]a ] ; then
         file=$(find . -empty -name $outputfile)
         if [ "$file" != "" ] ; then
            echo "Creando $outputfile ..."
            cat $outputfile.* > $outputfile && rm -f $outputfile.* && echo -e "${yellow}Archivo + + +$outputfile+ + + creado!!!${NC}"
         fi
      fi
   fi
   return 0
}

read -d '' comandosremotosTemplate << 'EOF'
cd REMOTEDIR
lista=$(find . -maxdepth 1 -type f | sort)

for i in $lista
do

   if [[ $(find ./$i -type f -size +SIZESPLITFILE 2>/dev/null) ]]; then
      split -a 4 -d -b SIZESPLITFILE $i $i. && rm $i
      f1=$(echo $(ls $i.*) | awk '{print $1}')
      f2=$(echo $(ls $i.*) | awk '{print $NF}')
      mv="mv $f1 ${f1}a; mv $f2 ${f2}z"
      eval "$mv"
   fi

done

files=$(find . -maxdepth 1 -type f | sort)
echo $files
exit 0
EOF

IFS=$' '
comandosremotos=$(echo $comandosremotosTemplate | sed -e "s/REMOTEDIR/$remotedirscaped/g" -e "s/SIZESPLITFILE/$sizesplitfile/g")
echo -e "Conectando al servidor remoto y haciendo 'split' a los archivos...\n"
files=$(ssh $remotesshaccount "$comandosremotos" | sed -e 's/\.\///g' -e 's/ /\n/g')

echo -e "\nSe incronizaran los siguientes archivos de ${sizesplitfile}B cada uno:\n"
echo "$files" | sed ':a;N;$!ba;s/\n/ , /g'

echo -e "\nSincronizando archivos con $numprocesos procesos concurrentes ...\n"
export -f myrsync
export bwlimit remotesshaccount remotedir localdir optsrsync1 optsrsync2
echo $files | xargs -I '{}' -P $numprocesos -n1 bash -c "myrsync '{}'" || exit -1

echo ""
cd $localdir/
lista=$(find . -maxdepth 1 -type f -name "*.0000a" )

IFS=$'\n'
for i in $lista
do
   outputfile=$(echo $i | sed 's/\.0000a//g')
   if [ -f $outputfile\.[0-9][0-9][0-9][0-9]z ] ; then
      if [ ! -f $outputfile ] ; then
         yellow='\033[1;33m'
         NC='\033[0m' # No Color
         echo -e "${yellow}Creando $outputfile ...${NC}"
         cat $outputfile.* > $outputfile && rm -f $outputfile.* && echo -e "${yellow}Archivo + + +$outputfile+ + + creado!!!${NC}"
      fi
   fi
done

echo "Done."
exit 0
