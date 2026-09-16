! yl_adapter_override -- the NO-OP-FREE stub linked into builds WITHOUT the adapter.
!
! Fem.f90 calls this external subroutine immediately before the model_ready anchor,
! guarded by `yl_adapter_mode` (set only by --adapter=on). Two builds exist:
!
!   * builds that link src/adapter/yl_adapter_entry.f90 get the real entry, which
!     adapts the deck and commits over the legacy globals;
!   * every other build -- `release` included -- links THIS file instead, so the
!     solver keeps its property of not depending on any adapter object file while
!     Fem.f90 still compiles and links.
!
! WHY THIS IS NOT A NO-OP
!   A stub that silently returned would make `--adapter=on` mean "run the legacy
!   path" in exactly the builds where the adapter is absent. That is the worst
!   possible reading of a fallback switch: the operator asks for the new path,
!   is told nothing, and gets the old one. The whole point of the M4 exit condition
!   "回退开关经过测试，但不会自动触发" is that the switch never decides anything by
!   itself. So this stub REFUSES, loudly, with UNSUPPORTED (exit 3).
!
! It takes no arguments, so no explicit interface is needed at the call site and
! Fem.f90 needs no `use` line -- which is what kept the change there to one line
! and left all three checkpoint anchors on their original line numbers.
subroutine yl_adapter_override()
  use yl_diag, only: diag_abort, EXIT_UNSUPPORTED
  implicit none
  call diag_abort('UNSUPPORTED', EXIT_UNSUPPORTED, 'yl_adapter_entry_stub', &
       'this binary was built without the adapter entry; --adapter=on is not ' // &
       'available here. Build tools/build.sh solver-adapter, or drop --adapter=on.')
end subroutine yl_adapter_override

!> The per-block half of the same switch, for the same reason: a build without the
!> adapter must refuse `--adapter=on` / `--input=` at every entry point, not just the
!> first. Silently returning here would leave block 2 running on block 1's loads.
subroutine yl_adapter_block_override(iblks)
  use iso_fortran_env, only: int32
  use yl_diag, only: diag_abort, EXIT_UNSUPPORTED
  implicit none
  integer(int32), intent(in) :: iblks
  if (iblks < 0) continue   ! the argument is used only to make the interface explicit
  call diag_abort('UNSUPPORTED', EXIT_UNSUPPORTED, 'yl_adapter_entry_stub', &
       'this binary was built without the adapter entry; a multi-block analysis on ' // &
       'the adapter path is not available here.')
end subroutine yl_adapter_block_override
