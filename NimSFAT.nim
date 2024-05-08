# Program to create, and interact with a virtual file system

#[
Implement SFAT file system: https://azrael.digipen.edu/~mmead/www/Courses/CS180/Simple-FS.html
Simple FAT

The SFAT filesystem will have 4 basic sections. These sections are the

super block - This describes the layout of the entire filesystem, e.g. number of sectors, sectors per cluster, bytes per sector, etc.
directory area - This maps the file's name to the disk blocks that contain the contents.
file allocation table - This keeps track of which data blocks are in-use and which are free using linked-list techniques.
data area - This is the bulk of the filesystem and is where the contents of all of the files are actually stored.
]#

let endOfSuperBlock = 32

var fat_available = [byte 0x00, 0x00]
var fat_reserved = ['\x00', '\x01']
# user data indicates the section where the data is in
var fat_userData_low = ['\x00', '\x02']
var fat_userData_high =['\xFF', '\xF6']

var fat_badCluster = ['\xFF', '\xF7']
var fat_endMarker_low = ['\xFF', '\xF8']
var fat_endMarker_high = ['\xFF', '\xFF']


type
    SuperBlock* = object
        total_sectors: uint16
        sectors_per_cluster: uint16
        bytes_per_sector: uint16
        available_sectors: uint16
        total_direntries: uint16
        available_direntries: uint16
        fs_type: char
        reserved: array[11, byte]
        label: array[8, byte]

type
    DirEntry* = object
        name: array[10, byte]
        fat_entry: uint16
        size: uint32

import streams
import sequtils
import strutils

proc initializeSuperBlock(vfsFileStream: FileStream): SuperBlock =
    var sBlock: SuperBlock
    sBlock = SuperBlock(
        total_sectors: vfsFileStream.readUint16(),
        sectors_per_cluster: vfsFileStream.readUint16(),
        bytes_per_sector: vfsFileStream.readUint16(),
        available_sectors: vfsFileStream.readUint16(),
        total_direntries: vfsFileStream.readUint16(),
        available_direntries: vfsFileStream.readUint16(),
        fs_type: vfsFileStream.readChar(), #File system type (FA for SFAT)
        reserved: [byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        label: [byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
    )
    return sBlock

proc createEmptyFileSystem(path: string) =
    echo "[+] Creating SFAT @", path
    var fileStream = newFileStream(path, fmWrite)


    # SuperBlock
    echo "\t|_ Initializing SuperBlock"
    var labelBytes: array[8, byte]
    var i = 0
    for c in "VFS-3":
        labelBytes[i] = cast[uint8](int(c))
        i += 1
    #[
    let sBlock = SuperBlock(
        total_sectors: 8,
        sectors_per_cluster: 1,
        bytes_per_sector: 16,
        available_sectors: 8,
        total_direntries: 4,
        available_direntries: 4,
        fs_type: '\xFA', #File system type (FA for SFAT)
        reserved: [byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        label: labelBytes
    )]#
        
    let sBlock = SuperBlock(
        total_sectors: 12000000,
        sectors_per_cluster: 1,
        bytes_per_sector: 16,
        available_sectors: 12000000,
        total_direntries: 4,
        available_direntries: 4,
        fs_type: '\xFA', #File system type (FA for SFAT)
        reserved: [byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        label: labelBytes
    )
    fileStream.write(sBlock) 

    # directory Entries
    echo "\t|_ Initializing Directory Entries"
    var dirEntriesSize = sBlock.available_direntries * 16
    i = 0
    while i < int(dirEntriesSize):
        fileStream.write('\x00')
        i += 1

    # File Allocation Table (FAT) table
    echo "\t|_ Initializing File Allocation Table (FAT)"
    var fatSize = sBlock.total_sectors * 2
    i = 0
    while i < int(fatSize):
        fileStream.write('\x00')
        i += 1

    # Data area
    echo "\t|_ Initializing Data Area"
    var dataAreaSize = sBlock.total_sectors * sBlock.bytes_per_sector
    i = 0
    while i < int(dataAreaSize):
        fileStream.write('\x00')
        i += 1
    fileStream.close()
    echo "[+] File system created"

proc toCString(bytes: openarray[byte]): cstring =
  let str = cast[cstring](bytes)
  return str

proc getDirEntries(inFileStream: FileStream, sblock: SuperBlock): seq[DirEntry] =
    # Update directory entries with filename 
    var usedDirEntries = (sBlock.total_direntries - sBlock.available_direntries)
    #echo "\t\t|_ Reading dirEntries. dirEnt used: ", usedDirEntries
    # Dir entries start after super block, set location
    inFileStream.setPosition(endOfSuperBlock)
    # Iterate over dir entries check for

    var seqDirEntries: seq[DirEntry]
    var index = 0
    while index < int(usedDirEntries):
        var dirEntry: DirEntry

        dirEntry = DirEntry(
            name: [byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
            fat_entry: 0,
            size: 0,
        )
        var status = inFileStream.readData(addr(dirEntry.name), 10)
        dirEntry.fat_entry = inFileStream.readUint16()
        dirEntry.size = inFileStream.readUint32()
        #echo "\t\t\t|-> ", toCString(dirEntry.name)
        #echo "\t\t\t|-> ", dirEntry.size
        seqDirEntries.add(dirEntry)
        index += 1

    return seqDirEntries

func toByteSeq*(str: string): seq[byte] {.inline.} =
    ## Converts a string to the corresponding byte sequence.
    @(str.toOpenArrayByte(0, str.high))

import math
func getFatsToAllocate(sBlock: SuperBlock, sizeOfFile: int): float =
    # Figure how many blocks to allocate
    var fatBlocksToAllocate = ceil(float(sizeOfFile) / (float(sBlock.bytes_per_sector)/2))
    if fatBlocksToAllocate mod 2 != 0:
        fatBlocksToAllocate = fatBlocksToAllocate + 1
    return fatBlocksToAllocate

# create file
proc copyFileToVFS(vfsPath: string, filePath: string) =

    echo "[+] Copying file ", filePath
    var inputFileStream = newFileStream(filePath, fmRead)
    var vfsFileStream = newFileStream(vfsPath, fmRead)
    
    var outFileStream = newStringStream(vfsFileStream.readAll())
    #outFileStream.write(vfsFileStream)
    vfsFileStream.setPosition(0)

    # 1. Superblock - Update available_sectors and available_direntries.
    # read super block
    var sBlock: SuperBlock = initializeSuperBlock(vfsFileStream)
    
    var status = vfsFileStream.readData(addr(sBlock.reserved), 11)
    status = vfsFileStream.readData(addr(sBlock.label), 8)

    echo "\t|_ Super block"
    echo "\t\t|-> total_sectors: ", sBlock.total_sectors
    echo "\t\t|-> sectors_per_cluster: ", sBlock.sectors_per_cluster
    echo "\t\t|-> bytes_per_sector: ", sBlock.bytes_per_sector
    echo "\t\t|-> available_sectors: ", sBlock.available_sectors
    echo "\t\t|-> total_direntries: ", sBlock.total_direntries
    echo "\t\t|-> available_direntries: ", sBlock.available_direntries
    echo "\t\t|-> fs_type: ", sBlock.fs_type
    echo "\t\t|-> reserved: ", sBlock.reserved
    echo "\t\t|-> label: ", toCString(sBlock.label)
    #echo toCString(sBlock.label)
    # Check available dir entries
    if sBlock.available_direntries == 0:
        echo "[ERROR] No direntries available"
        return
    

    # 2. Directory entries - Update a directory entry with the filename, the FAT entry, and the file size.
    # init
    var dirEntry: DirEntry
    dirEntry = DirEntry(
        name: [byte 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
        fat_entry: 0,
        size: 0,
    )
    # Get FAT location
    var dirEntries = getDirEntries(vfsFileStream, sBlock)

    # Get size of all FATs before
    var totalSectorsUsed = 0
    for dir in dirEntries:
        totalSectorsUsed += int(getFatsToAllocate(sBlock, cast[int](dir.size)))

    # FAT entry
    dirEntry.fat_entry = cast[uint16](int(totalSectorsUsed/2))

    echo "\t|_ Dir Entry to be used: ", len(dirEntries)
    # File name
    var splitFilePath = filePath.split("\\")
    var filename = splitFilePath[len(splitFilePath)-1]
    echo "\t\t|-> File name ", filename
    # set location 
    outFileStream.setPosition(endOfSuperBlock + (int(sBlock.bytes_per_sector) * len(dirEntries)))
    if len(filename) < 10:
        echo "\t\t|_ Appending bytes to filename"
        var fn: seq[byte] = toByteSeq(filename)
        while len(fn) < 10:
            fn.add(0)
        for c in fn:
            outFileStream.write(c)
        echo "\t\t|->", fn
    else:
        outFileStream.write(filename)
    # FAT entry
    echo "\t\t|-> FAT entry ", dirEntry.fat_entry
    outFileStream.write(dirEntry.fat_entry)
    # Size 
    var tmp = inputFileStream.readAll()
    var sizeOfFile = inputFileStream.getPosition()

    echo "\t\t|-> Size ", sizeOfFile
    # cast to uint32 to ensure we dont overwrite FAT table
    outFileStream.write(cast[uint32](sizeOfFile))

    



    # 3. FAT - Update the corresponding FAT entry.
    # init
    var fatBaseLocation = endOfSuperBlock + int(sBlock.total_direntries * sBlock.bytes_per_sector)
    #echo "er ",fatBaseLocation*2
    var fatBlocksToAllocate = int(getFatsToAllocate(sBlock, sizeOfFile))
    echo "\t|_ Sections used by file: ", fatBlocksToAllocate
    

    echo "\t|_ Sections used so far: ", totalSectorsUsed
    # set location to write entires at
    var fatWriteLoc = fatBaseLocation + totalSectorsUsed

    # Update FAT
    outFileStream.setPosition(fatWriteLoc)
    # write FAT entries
    var fatEntry: seq[uint16]
    var index = 0
    while true:
        if fatBlocksToAllocate > 2:
            index += 1
            fatEntry.add(cast[uint16](int(totalSectorsUsed/2) + index))
            fatBlocksToAllocate -= 2
        else:
            fatEntry.add(0xFFFF)
            echo "\t\t|_ FAT value", fatEntry
            echo "\t\t|_ FAT written @", toHex(outFileStream.getPosition())
            for f in fatEntry:
                echo "\t\t|-> FAT value written: ", toHex(f)
                outFileStream.write(f) 
            break

    echo "\t|_ Updated available_direntries"
    sBlock.available_direntries = sBlock.available_direntries - 1
    outFileStream.setPosition(0)
    outFileStream.write(sBlock) 
    echo "\t|-> Updated direntries"



    # 4. Data area - Use the block(s) pointed to by the FAT entry/entries.
    echo "\t|_ Writing contents to data area"
    # Get offset to Data area
    var dataAreaOffset = endOfSuperBlock + int(sBlock.total_direntries) * int(sBlock.bytes_per_sector) + int(sBlock.bytes_per_sector)

    # Get FAT entry
    var writeLoc = dataAreaOffset + int(dirEntry.fat_entry) * int(sBlock.bytes_per_sector)
    # write contents
    outFileStream.setPosition(writeLoc)
    inputFileStream.setPosition(0)
    outFileStream.write(inputFileStream.readAll()) 

    # save
    vfsFileStream.close()
    var svfsFileStream = newFileStream(vfsPath, fmWrite)
    outFileStream.setPosition(0)
    svfsFileStream.write(outFileStream.readAll())
    outFileStream.close()
    svfsFileStream.close()
    echo "[+] File created"

# List all files and their sizes
proc ls(filePath: string) =
    var vfsFileStream = newFileStream(filePath, fmRead)

    var sBlock: SuperBlock = initializeSuperBlock(vfsFileStream)

    var dirEntries = getDirEntries(vfsFileStream, sBlock)
    for dir in dirEntries:
        echo toCString(dir.name)

proc toString(str: seq[char]): string =
  result = newStringOfCap(len(str))
  for ch in str:
    add(result, ch)

# Get file contents by name
proc cat(filePath: string, fileName: string) =
    var vfsFileStream = newFileStream(filePath, fmRead)
    
    var sBlock: SuperBlock = initializeSuperBlock(vfsFileStream)

    var targetDirEntry: DirEntry
    var dirEntries = getDirEntries(vfsFileStream, sBlock)
    for dir in dirEntries:
        var dirName = $(toCString(dir.name))
        if dirName.contains(fileName):
            targetDirEntry = dir
            break
    if toCString(targetDirEntry.name) == "":
        echo "[ERROR] No such file exsist"
        quit(-1)


    # Read Contents
    vfsFileStream.setPosition(endOfSuperBlock + int(sBlock.total_direntries * sBlock.bytes_per_sector) + int(sBlock.bytes_per_sector) + int(targetDirEntry.fat_entry * sBlock.bytes_per_sector))
    var res: seq[char]
    var index = 0
    # Does not read files correctly
    while index < int(targetDirEntry.size):
        stdout.write vfsFileStream.readChar()
        #res.add(vfsFileStream.readChar())
        index += 1
    #echo toString(res)

proc extractFile(filePath: string, fileName: string, destinationPath: string) =
    var vfsFileStream = newFileStream(filePath, fmRead)
    
    var sBlock: SuperBlock = initializeSuperBlock(vfsFileStream)

    var targetDirEntry: DirEntry
    var dirEntries = getDirEntries(vfsFileStream, sBlock)
    for dir in dirEntries:
        var dirName = $(toCString(dir.name))
        if dirName.contains(fileName):
            targetDirEntry = dir
            break
    if toCString(targetDirEntry.name) == "":
        echo "[ERROR] No such file exsist"
        quit(-1)


    # Read Contents
    vfsFileStream.setPosition(endOfSuperBlock + int(sBlock.total_direntries * sBlock.bytes_per_sector) + int(sBlock.bytes_per_sector) + int(targetDirEntry.fat_entry * sBlock.bytes_per_sector))
    var res = newFileStream(destinationPath, fmWrite)
    var index = 0

    # Does not read files correctly
    while index < int(targetDirEntry.size):
        res.write(vfsFileStream.readUint8())
        index += 1
    #echo toString(res)

# Disk Free: get how much space is left in the file system
proc df(filePath: string) =
    var vfsFileStream = newFileStream(filePath, fmRead)

    var sBlock: SuperBlock = initializeSuperBlock(vfsFileStream)

    var dirEntries = getDirEntries(vfsFileStream, sBlock)
    var totalSpace = sBlock.total_sectors * sBlock.bytes_per_sector
    var totalSpaceUsed = 0
    for dir in dirEntries:
        totalSpaceUsed += int(dir.size)
    
    echo "Filesystem\tBlocks\tUsed\tAvailable\tUse%"
    echo "/\t\t",sBlock.total_sectors,"\t",totalSpaceUsed,"\t",(int(totalSpace)-int(totalSpaceUsed)),"\t\t", round((int(totalSpaceUsed) / int(totalSpace))*100), "%"
        
import os
proc printHelp() =
    echo """
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
    """
    quit(-1)

var helpVariations = @["help", "-h", "--help", "/h", "/help"]

if paramCount() == 0:
    printHelp()

if paramStr(1) in helpVariations:
    printHelp()

# Menu
if paramStr(1) == "-create-vfs":
    if paramCount() != 2:
        echo "Please specify all required inputs"
        quit(-1)
    createEmptyFileSystem(paramStr(2))
    quit()

if paramStr(1) == "-insert":
    if paramCount() != 3:
        echo "Please specify all required inputs"
        quit(-1)
    copyFileToVFS(paramStr(2), paramStr(3))
    quit()

if paramStr(1) == "-extract":
    if paramCount() != 4:
        echo "Please specify all required inputs"
        quit(-1)
    extractFile(paramStr(2), paramStr(3), paramStr(4))
    quit()

if paramStr(1) == "-ls":
    if paramCount() != 2:
        echo "Please specify all required inputs"
        quit(-1)
    ls(paramStr(2))
    quit()

if paramStr(1) == "-cat":
    if paramCount() != 3:
        echo "Please specify all required inputs"
        quit(-1)
    cat(paramStr(2), paramStr(3))
    quit()

if paramStr(1) == "-df":
    if paramCount() != 2:
        echo "Please specify all required inputs"
        quit(-1)
    df(paramStr(2))
    quit()

