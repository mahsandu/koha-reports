SELECT
    cardnumber,
    barcode,
    itemnumber,
    DueDate,
    ReturnDate,
    DueDays,
    Holidays,
    (DueDays - Holidays) AS FineDays,
    ((DueDays - Holidays) * 2) AS TotalFine,
    AmountOutStanding,
    Amount,
    status,
    credit_type_code,
    DATE_FORMAT(CURDATE(), '%d-%m-%Y') AS Today
FROM (
    SELECT
        b.cardnumber AS cardnumber,
        i.barcode AS barcode,
        a.itemnumber AS itemnumber,
        DATE_FORMAT(o.date_due, '%d-%m-%Y') AS DueDate,
        DATE_FORMAT(o.returndate, '%d-%m-%Y') AS ReturnDate,
        CAST(DATEDIFF(DATE_FORMAT(o.returndate, '%Y-%m-%d'), DATE_FORMAT(o.date_due, '%Y-%m-%d')) - 7 AS SIGNED) AS DueDays,
        CAST((DATEDIFF(DATE_FORMAT(o.returndate, '%Y-%m-%d'), DATE_FORMAT(o.date_due, '%Y-%m-%d')) -7) / 7 AS SIGNED)AS Holidays,
        CAST(a.amountoutstanding AS SIGNED) AS AmountOutStanding,
        CAST(a.amount AS SIGNED) AS Amount,
        a.status AS status,
        a.credit_type_code AS credit_type_code
    FROM
        (
            (
                accountlines a
                LEFT JOIN old_issues o ON o.itemnumber = a.itemnumber
            )
            LEFT JOIN items i ON i.itemnumber = a.itemnumber
        )
        LEFT JOIN borrowers b ON b.borrowernumber = a.borrowernumber
    WHERE
        a.amountoutstanding > 0 AND
        a.status='RETURNED'
        -- Replace with the itemnumber you want to filter by
    GROUP BY
        a.borrowernumber
) AS DerivedTable;

