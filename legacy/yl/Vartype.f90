module variable_types
implicit none

		integer,parameter::k_min   =selected_int_kind(1),                         &
                       k_short =selected_int_kind(4),                             &
                       k_int   =kind(0),                                          &
                       k_long  =selected_int_kind(range(0)+1),                    &
                       k_real  =kind(0.0),                                        &
                       k_double=kind(0d0),                                        &
                       k_quad  =selected_real_kind(precision(0d0)+1)
		integer,parameter::ink=k_int,irk=k_double

end module variable_types  
 