



# 𓃕DeSQL SQL Parser




<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [𓃕DeSQL SQL Parser](#%F0%93%83%95desql-sql-parser)
  - [To Do](#to-do)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->




# 𓃕DeSQL SQL Parser

<!-- clarify relation to 𓆤DBay -->

🚧 Work in progress 🚧

![](art/Screenshot 2022-02-11 at 20.20.17.png)

![](art/Screenshot 2022-02-11 at 20.24.18.png)


## To Do

* **[+]** add location information
* **[–]** fix (many) faulty location data (stop equals or precedes start line, column NR)
* **[–]** parse multiple statements
* **[–]** at present, comments and stuff the parser doesn't understand are left out of the result
  which constitues silent failure; ensure 100% source code coverage (whitespace may be left out,
  but not comments and also not unsyntactic garbage)
* **[–]** fix line, column numbers for coverage misses (whitespace and material stretches)



