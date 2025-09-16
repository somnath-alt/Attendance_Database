USE somDB;
SELECT * FROM student1;
SET SQL_SAFE_UPDATES=0;
UPDATE student
SET marks = 45
WHERE name = "Ravi";
SELECT * FROM student;

UPDATE student1
SET marks = 45
WHERE name = "Kohli";
SELECT * FROM student1;
