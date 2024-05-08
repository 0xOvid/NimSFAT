# NimSFAT
Nim implementation of the SFAT file system. SFAT is a simplified version of the FAT16 file system


# Usage
```
███╗   ██╗██╗███╗   ███╗      ███████╗███████╗ █████╗ ████████╗
████╗  ██║██║████╗ ████║      ██╔════╝██╔════╝██╔══██╗╚══██╔══╝
██╔██╗ ██║██║██╔████╔██║█████╗███████╗█████╗  ███████║   ██║
██║╚██╗██║██║██║╚██╔╝██║╚════╝╚════██║██╔══╝  ██╔══██║   ██║
██║ ╚████║██║██║ ╚═╝ ██║      ███████║██║     ██║  ██║   ██║
╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝      ╚══════╝╚═╝     ╚═╝  ╚═╝   ╚═╝   
    Simple FAT implemented in nim - by 0x0vid

    -help - Print this menu
    -create-vfs [vfs-file-name] - Create a new vfs
    -insert [vfs-file-name] [file path] - Copy file to vfs
    -extract [vfs-file-name] [file name] [file dest path] - Extract file from system to specified path
    -ls [vfs-file-name] - List files in vfs
    -cat [vfs-file-name] [file name] - Print file contents from vfs file
    -df [vfs-file-name]  - get stats of vfs

    Options:
    [vfs-file-name] - Name for file where vfs is written
    [file path] - Path for file
    [file name] - Vfs file name
    [file dest path] - File destination
```
