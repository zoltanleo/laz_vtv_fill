### A test project to study the speed of fetching data from a database and populating a tree with this data


--------

v.0.0.6

- removed the fork of ibx components by Rik (aka Yury Kopnin)

--------

v.0.0.5

- added the fork of ibx components by Rik (aka Yury Kopnin)

--------

v.0.0.4

- added result picture

--------

v.0.0.3

- implemented selection and display of child records for each node

--------

v.0.0.2
- added `id_parent` field
- removed several root entries to break the continuous `id` sequence
added child records whose `id_parent` is not equal to `0`

--------

v.0.0.1
- done loading 1000 records in the main thread
- done loading the rest of the records in an additional stream

The tree does not store data within itself, but displays data from the memory dataset