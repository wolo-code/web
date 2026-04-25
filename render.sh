#! /bin/bash

cd /app

tiggu/build.sh app/project
tiggu/build.sh site/project

shopt -s extglob

copy_dot_dirs() {
  local source_dir=$1
  local dest_dir=$2
  
  shopt -s extglob

  cp -r $source_dir/* $dest_dir
  for dir in "$source_dir"/.!(.|git); do
    if [ -d "$dir" ] || [ -f "$dir" ]; then
      cp -r "$dir" "$dest_dir"
    fi
  done
}

# moving in app files after web files in order to overwrite

copy_dot_dirs site/project/interim project/build/interim
copy_dot_dirs site/project/public project/build/public
copy_dot_dirs app/project/interim project/build/interim
copy_dot_dirs app/project/public project/build/public
