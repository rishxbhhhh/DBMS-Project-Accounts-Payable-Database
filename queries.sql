use dswproject;
create table invoices(
  invoice_id int primary key AUTO_INCREMENT,
  vendor_id int not null,
  invoice_number VARCHAR(50) not null,
  invoice_date date not null,
  invoice_total decimal(9, 2) default 0,
  credit_total decimal(9, 2) DEFAULT 0,
  terms_id int not null,
  invoice_due_date date,
  payment_date date
);
CREATE table terms(
  terms_id INT PRIMARY key AUTO_INCREMENT,
  terms_description VARCHAR(50) NOT NULL,
  terms_due_days int
);
CREATE TABLE vendors(
  vendor_id int PRIMARY key AUTO_INCREMENT,
  vendor_name VARCHAR (50) not null,
  vendor_address1 VARCHAR (50) not null,
  vendor_address2 VARCHAR (50),
  vendor_city VARCHAR (50),
  vendor_state char(20),
  vendor_zip_code VARCHAR (20),
  vendor_phone VARCHAR (50),
  vendor_contact_last_name VARCHAR (50),
  vendor_contact_first_name VARCHAR (50),
  default_terms_id int not null,
  default_account_number int not null
);
CREATE table general_ledger_accounts(
  account_number int PRIMARY KEY AUTO_INCREMENT,
  account_description VARCHAR (50)
);

CREATE TABLE invoice_line_items(
    invoice_id int not null,
    invoice_sequence int not null,
    account_number int not null,
    line_item_amount decimal(9,2) not null,
    line_item_description VARCHAR (100),
    PRIMARY key(invoice_id, invoice_sequence),
    FOREIGN key(account_number) REFERENCES general_ledger_accounts (account_number)
);

alter table invoices
add constraint invoices_fk_vendors FOREIGN key (vendor_id) REFERENCES vendors (vendor_id),
add constraint invoices_fk_terms FOREIGN key (terms_id) REFERENCES terms (terms_id);

ALTER TABLE vendors
add constraint vendors_fk_terms FOREIGN key (default_terms_id) REFERENCES terms (terms_id),
add constraint vendors_fk_accounts FOREIGN key (default_account_number) REFERENCES general_ledger_accounts (account_number);



/*1 trigger: BEFORE delete on terms table as it is foreign key constrained*/
DELIMITER //
CREATE TRIGGER deleteTermsNotAllowed 
BEFORE DELETE ON terms FOR EACH ROW 
BEGIN 
signal sqlstate '49001' SET message_text = "DELETE on terms forbidden (foreign key restrained)!";
END // 
DELIMITER ;
DELETE FROM terms;

/*2 trigger: BEFORE delete on general Ledger Accounts table as it is foreign key constrained*/
DELIMITER //
CREATE TRIGGER deleteAccountsNotAllowed 
BEFORE DELETE ON general_ledger_accounts FOR EACH ROW 
BEGIN 
signal sqlstate '49002' SET message_text = "DELETE on general_ledger_accounts forbidden (foreign key restrained)!";
END // 
DELIMITER ;
DELETE FROM general_ledger_accounts;

/*3 trigger: BEFORE INSERT on invoices table discount 10% if invoice_total > 100000 */
DELIMITER //
CREATE TRIGGER updateInvoiceDiscount
BEFORE INSERT ON invoices FOR EACH ROW
BEGIN
IF new.invoice_total > 100000 THEN
SET new.invoice_total = (new.invoice_total)*0.9;
END IF;
END //
DELIMITER ;
INSERT INTO invoices(vendor_id,invoice_number,invoice_date,invoice_total,credit_total,terms_id,invoice_due_date,payment_date) 
VALUES (50,'499700','2012-08-23',1000099,48379.32,1,'2012-11-23','2012-09-23');
SELECT (invoice_total) FROM invoices
WHERE vendor_id = 50 AND terms_id = 1;

/*4 Procedure: To get names of all vendors*/
DELIMITER //
CREATE PROCEDURE getvendors(INOUT vendorslist VARCHAR (10000))
BEGIN 
DECLARE isdone INT DEFAULT 0;
DECLARE vendorname varchar(50);
DECLARE vendorcursor CURSOR FOR
SELECT vendor_name from vendors;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET isdone = 1;
OPEN vendorcursor;
vendorloop: LOOP
FETCH vendorcursor INTO vendorname;
IF isdone = 1 THEN
LEAVE vendorloop;
END IF;
SET vendorslist = CONCAT(vendorname, ", ", vendorslist);
END LOOP vendorloop;
CLOSE vendorcursor;
END //

DELIMITER ;
SET @vendorlist = "";
CALL getvendors(@vendorlist);
SELECT @vendorlist;

/*5: procedure to add late fees*/
-- there were no dates greater than current date so added a few
update invoices
SET payment_date = '2021-10-21'
WHERE invoice_id IN (1,3,5,7,9);

-- some invoice_total values were offlimit, thus
update invoices
SET invoice_total = 100000
WHERE invoice_total > 100000

-- glimpse of values about to be updated
select invoice_id,invoice_total,'NOT updated payment' from invoices
WHERE invoice_id IN (1,3,5,7,9);

-- procedure
DELIMITER //
CREATE procedure addlatepayment()
BEGIN
DECLARE isdone INT DEFAULT 0;
DECLARE invid INT DEFAULT 0;
DECLARE invtotal INT DEFAULT 0;
DECLARE oldpayment INT DEFAULT 0;
DECLARE invpdate date DEFAULT 0;
DECLARE invcursor CURSOR FOR
SELECT invoice_id,payment_date,invoice_total FROM invoices;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET isdone = 1;
OPEN invcursor;
invloop: LOOP
FETCH invcursor INTO invid,invpdate,invtotal;
SET oldpayment = invtotal;
IF isdone = 1 THEN
LEAVE invloop;
END IF;
IF invpdate > CURDATE() THEN
SET invtotal = invtotal * 1.05;
UPDATE invoices
SET invoice_total = invtotal
WHERE invoice_id = invid;
SELECT invoice_id as ID,oldpayment as PREVIOUS_TOTAL,invoice_total as UPDATED_TOTAL,'UPDATED' as STATUS from invoices
WHERE invoice_id = invid;
END IF;
END LOOP invloop;
SELECT 'Late dues added successfully';
CLOSE invcursor;
END //
DELIMITER ;

-- calling PROCEDURE 
call addlatepayment();
--actually whole table is traversed but 
--here only those tuples shown which were actually updated


/*6: procedure to show due payments*/

-- procedure
DELIMITER //
CREATE procedure showduepayments()
BEGIN
DECLARE isdone INT DEFAULT 0;
DECLARE invid INT DEFAULT 0;
DECLARE invtotal INT DEFAULT 0;
DECLARE invpdate date DEFAULT 0;
DECLARE cursorinv CURSOR FOR
SELECT invoice_id,payment_date,invoice_total FROM invoices;
DECLARE CONTINUE HANDLER FOR NOT FOUND SET isdone = 1;
OPEN cursorinv;
invloop: LOOP
FETCH cursorinv INTO invid,invpdate,invtotal;
IF isdone = 1 THEN
LEAVE invloop;
END IF;
IF invpdate > CURDATE() THEN
SELECT invoice_id as ID,payment_date,invoice_total as DUE_INVOICE,'PENDING' as STATUS from invoices
WHERE invoice_id = invid;
END IF;
END LOOP invloop;
CLOSE cursorinv;
END //
DELIMITER ;

-- calling PROCEDURE 
call showduepayments();


/*7: Timestamp trigger to run procedure addlatepayment() daily once*/
-- to run scheduled events event organiser should be ON
-- set it to 0 to turn it OFF
SET GLOBAL event_scheduler = 1;

-- sample event to see results if working
CREATE EVENT updatepayment
ON SCHEDULE EVERY 5 SECOND
DO
CALL dswproject.addlatepayment();

select invoice_id,invoice_total from invoices
where invoice_id IN (1,3,5,7,9);

-- repeat after 5 seconds
select invoice_id,invoice_total from invoices
where invoice_id IN (1,3,5,7,9);

--dropping sample event
drop event if exists updatepayment;
-- actual event
CREATE EVENT updatepayment
ON SCHEDULE EVERY 1 DAY
DO
CALL dswproject.addlatepayment();