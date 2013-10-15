###
# Test script used whilst developing the dba.coffee library
###

stampede = require '../lib/stampede'

t1 = new stampede.time()
console.log t1.toString()

t2 = new stampede.time(10, 30, 15)
console.log t2.toString()

console.log t1.add(t2).toString()

console.log t1.add(t2).toString()
