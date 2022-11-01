select
  `b`.`biblionumber` AS `biblionumber`,
  concat(
    if(
      char_length(`systempreferences`.`value`),
      concat(`systempreferences`.`value`),
      ''
    ),
    '/cgi-bin/koha/opac-image.pl?thumbnail=1&biblionumber=',
    `b`.`biblionumber`
  ) AS `cover`,
  `b`.`author` AS `author`,
  `b`.`title` AS `title`,
  `b`.`subtitle` AS `subtitle`,
  extractvalue(
    `m`.`metadata`,
    '//datafield[@tag="245"]/subfield[@code>="c"]'
  ) AS `credits`,
  `bi`.`editionstatement` AS `edition`,
  `bi`.`place` AS `place`,
  `bi`.`publishercode` AS `publisher`,
  extractvalue(
    `m`.`metadata`,
    '//datafield[@tag="260"]/subfield[@code>="c"]'
  ) AS `year`,
  count(`i`.`barcode`) AS `copy`,
  concat(
    extractvalue(
      `m`.`metadata`,
      '//datafield[@tag="650"]/subfield[@code>="a"]'
    )
  ) AS `subjects`
from
  (
    `systempreferences`
    join (
      (
        (
          (
            (
              `biblio` `b`
              join `virtualshelfcontents` `v` on(`v`.`biblionumber` = `b`.`biblionumber`)
            )
            left join `biblioitems` `bi` on(`bi`.`biblionumber` = `b`.`biblionumber`)
          )
          left join `items` `i` on(`i`.`biblionumber` = `b`.`biblionumber`)
        )
        left join `biblio_metadata` `m` on(`m`.`biblionumber` = `b`.`biblionumber`)
      )
      left join `cover_images` `c` on(`c`.`biblionumber` = `b`.`biblionumber`)
    )
  )
where
  `i`.`barcode` is not null
  and (
    extractvalue(
      `m`.`metadata`,
      '//datafield[@tag="526"]/subfield[@code="b"]'
    ) = 'Economis'
    or extractvalue(
      `m`.`metadata`,
      '//datafield[@tag="650"]/subfield[@code="a"]'
    ) like 'Econ%'
    or extractvalue(
      `m`.`metadata`,
      '//datafield[@tag="650"]/subfield[@code="a"]'
    ) like 'Fin%'
  )
  and `systempreferences`.`variable` = 'OPACBaseURL'
group by
  `b`.`biblionumber`
order by
  `b`.`title`