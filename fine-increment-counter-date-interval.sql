SELECT
    borrowers.cardnumber,borrowers.categorycode,borrowers.surname,issues.date_due,
    (TO_DAYS(curdate())-TO_DAYS( date_due)) AS daysoverdue,
    items.barcode AS 'Accession Number',
    biblio.title,biblio.author,
    IF((TO_DAYS(curdate())-TO_DAYS( date_due))<=15,(TO_DAYS(curdate())-TO_DAYS( date_due)),
      IF((TO_DAYS(curdate())-TO_DAYS( date_due))<=30,2*(TO_DAYS(curdate())-TO_DAYS( date_due))-15,5*(TO_DAYS(curdate())-TO_DAYS( date_due))-105))
     AS fine
  FROM borrowers
  LEFT JOIN issues ON (borrowers.borrowernumber=issues.borrowernumber)
  LEFT JOIN items ON (issues.itemnumber=items.itemnumber)
  LEFT JOIN biblio ON (items.biblionumber=biblio.biblionumber)
  WHERE (borrowers.categorycode=<<Patron Category|categorycode>>) AND (TO_DAYS(curdate())-TO_DAYS(date_due)) > '0'
  ORDER BY borrowers.cardnumber ASC