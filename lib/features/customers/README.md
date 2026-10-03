# features/customers

Customer records that jobs are created for: name, phone numbers, address and
site notes for the technician.

**Phase 3 status: structure only — nothing is implemented in this folder yet.**

## Layers

| Folder | Contents | May depend on |
|---|---|---|
| `domain/` | `Customer` entity, the `CustomerRepository` contract, use cases (`GetCustomers`, `SearchCustomers`, `CreateCustomer`, `UpdateCustomer`, `DeleteCustomer`) | Dart only, plus `core/errors` |
| `data/` | `CustomerRemoteDataSource`, `CustomerLocalDataSource`, DTO models, `CustomerRepositoryImpl` | `domain/`, `core/network`, `core/database` |
| `presentation/` | `CustomersCubit` + states, customers list/detail/form pages, page-private widgets | `domain/` use cases only |

## Notes

- This is the most offline-hostile feature of the app: a technician often meets
  a new customer on site with no signal, so **creation must work fully offline**
  with a client-generated UUID and be pushed later.
- Phone numbers and addresses are used offline for calls and navigation, so the
  cached copy is the source of truth for the field technician.
- Duplicate detection / merging is a server-side concern and is not modelled
  here yet.
