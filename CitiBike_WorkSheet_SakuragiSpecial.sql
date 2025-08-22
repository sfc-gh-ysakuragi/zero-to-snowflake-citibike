/*******************************************************************************
    3. データロードの準備
*******************************************************************************/

-- コマンドで操作する場合は以下を順に実行 
-- Tripデータを入れるDB-スキーマを用意

use role sysadmin;
create or replace database citibike; -- CitiBikeデータベースを作成

use database citibike;
use schema public; -- CitiBikeデータベースの下に,publicスキーマを作成
use warehouse compute_wh;


/*******************************************************************************
    4. データ読み込みの準備
*******************************************************************************/

/* 4-1) Tripsテーブルを作成 */
create or replace table trips
(tripduration integer,
starttime timestamp,
stoptime timestamp,
start_station_id integer,
start_station_name string,
start_station_latitude float,
start_station_longitude float,
end_station_id integer,
end_station_name string,
end_station_latitude float,
end_station_longitude float,
bikeid integer,
membership_type string,
usertype string,
birth_year integer,
gender integer);


/* 4-2) 外部ステージ作成 
 ※UIから作成済みの場合は実行しないで次のコマンドへ */
create or replace stage citibike_trips
    url = 's3://snowflake-workshop-lab/japan/citibike-trips/';

--> 外部ステージにあるファイルの一覧を確認
list @citibike_trips;
 -- 年毎に複数ファイルに分割されて格納されている
 -- AWS S3上に置かれているデータは 377個のファイル(gz圧縮後 1.9GB), 6,150万行

 
/* 4-3) File Format作成 
 Snowflakeのテーブルに綺麗にロードするため */ 
create or replace file format csv type='csv'
  compression = 'auto' field_delimiter = ',' record_delimiter = '\n'
  skip_header = 0 field_optionally_enclosed_by = '\042' trim_space = false
  error_on_column_count_mismatch = false escape = 'none' escape_unenclosed_field = '\134'
  date_format = 'auto' timestamp_format = 'auto' null_if = ('') comment = 'file format for ingesting data for zero to snowflake';

--> 作成した File Format を確認
show file formats in database citibike;


/*******************************************************************************
    5.データの読み込み
        ・スケールアップを体感!!
        ・AWS-S3内の情報 377個のファイル(gz圧縮後 1.9GB), 6,150万行
*******************************************************************************/
/* 5-1) ウェアハウスのサイズ確認 
    XSの場合, Sサイズに変更 */

    
/* 5-2)外部ステージからデータロード (Sサイズ) */
copy into trips from @citibike_trips file_format=csv PATTERN = '.*csv.*' ;
--> 計測値を記載 [**]秒 (Sサイズ)


-- ここからスケールアップでどれくらい早くなるかを体感!!
--> Trips テーブルにロードした全てのデータ、メタデータを削除 */
truncate table trips;
--> Trips テーブルの内容確認 ※何も表示されないことを確認
select * from trips limit 10;


/* 5-3)ウェアハウスのサイズをLサイズにスケールアップ! */
alter warehouse compute_wh set warehouse_size='large';

--> ウェアハウスのサイズがLサイズに変わっているか確認
show warehouses;


/* 5-4) 外部ステージからのデータロード (Lサイズ) */
copy into trips from @citibike_trips file_format=csv PATTERN = '.*csv.*' ;
--> 計測値を記載 [**]秒 (Lサイズ)

-- 倍くらい早くなりましたか?


/* 5-5) ウェアハウスのサイズをSサイズに戻しておきます */
alter warehouse compute_wh set warehouse_size='small';



/*******************************************************************************
    6. クエリ、リザルトキャッシュ、およびクローンの操作
*******************************************************************************/

/* 6-1) Trips テーブルの内容確認 */
select * from trips limit 20;


/* 6-2) 2017年下半期以降のデータを取得するSELECT文を実行 */
select  monthname(starttime),gender, count(*) --月x性別ごとの利用数
from trips
where starttime > '2017-07-01 00:00:00'
group by monthname(starttime), gender;
--> 表示項目や条件を絞ることで,マイクロパーティションのプルーニングが効く
--> クエリプロファイルで確認


/* 6-3) キャッシュを体験 - METADATA */
-- 　サービス総利用回数を確認
select count(*) from trips;


/* 6-4-1) キャッシュを体験 - クエリリザルトキャッシュ */
-- Citibike の使用状況に関する1時間ごとの基本統計量を確認
select date_trunc('hour', starttime) as "date", -- 1時間ごと
count(*) as "num trips",                        -- 利用回数
avg(tripduration)/60 as "avg duration (mins)",  -- 平均移動時間
avg(haversine(start_station_latitude, start_station_longitude, end_station_latitude, end_station_longitude)) as "avg distance (km)"                                  -- 平均移動距離
from trips
group by 1 order by 1;
--> 計測値を記載 [**]秒 (Sサイズ)
--> クエリプロファイルで,結果出力までの変遷を確認

/* 6-4-2) 6-4-1と同じデータに同じクエリを実行 */
select date_trunc('hour', starttime) as "date", -- 1時間ごと
count(*) as "num trips",                        -- 利用回数
avg(tripduration)/60 as "avg duration (mins)",  -- 平均移動時間
avg(haversine(start_station_latitude, start_station_longitude, end_station_latitude, end_station_longitude)) as "avg distance (km)"                                  -- 平均移動距離
from trips
group by 1 order by 1; 
--> 計測値を記載 [**]秒 (Sサイズ)
--> クエリプロファイルで,結果出力までの変遷を確認
--> リザルトキャッシュが効いていることを確認

--> チャートでデータを分析してみましょう!!
--> 季節性がありそう?!
--> 講師はTableauで分析してみます!!


/* 6-5)キャッシュを体験 - データキャッシュ */
--2019年以降のデータを取得するSELECT文を実行
select  monthname(starttime),gender, count(*) --月x性別ごとの利用数
from trips
where starttime > '2018-01-01 00:00:00'
group by monthname(starttime), gender;


--2018年以降のデータを取得するSELECT文を実行
select  monthname(starttime),gender, count(*) --月x性別ごとの利用数
from trips
where starttime > '2017-01-01 00:00:00'
group by monthname(starttime), gender;
--> クエリプロファイルでキャッシュからスキャンされた割合を確認


/*******************************************************************************
    7. 半構造化データ、ビュー、結合の操作
        ・6-5で季節性がありそうなことが判明
        ・天気による傾向もあるのでは?!
        　→ お天気データを取り込んで分析したい!!
*******************************************************************************/

/* 7-1)Weather データベースの作成  */
create database weather;

-- これからクエリ実行するロール,ウェアハウス,データベース,スキーマを指定
use role sysadmin;
use warehouse compute_wh;
use database weather;
use schema public;


/* 7-2) JSON データロード用テーブルの作成 */
create or replace table json_weather_data (v variant);
--> Variant型：なんでもぶち込める型 (半構造化のELTを実現!!)


/* 7-3) 外部ステージ(Weather用)作成 */
create stage nyc_weather
url = 's3://snowflake-workshop-lab/zero-weather-nyc';

--> 外部ステージにあるファイルの一覧を確認
list @nyc_weather;


/* 7-4) 半構造化データ（JSON）のロード  */
copy into json_weather_data
from @nyc_weather 
    file_format = (type = json strip_outer_array = true);

--> ロードした JSON データの確認
select * from json_weather_data limit 10;


/* 7-5) 半構造化データを構造化して利用するためにビューを作成 */
create or replace view json_weather_data_view as
select
    v:obsTime::timestamp as observation_time,
    v:station::string as station_id,
    v:name::string as city_name,
    v:country::string as country,
    v:latitude::float as city_lat,
    v:longitude::float as city_lon,
    v:weatherCondition::string as weather_conditions,
    v:coco::int as weather_conditions_code,
    v:temp::float as temp,
    v:prcp::float as rain,
    v:tsun::float as tsun,
    v:wdir::float as wind_dir,
    v:wspd::float as wind_speed,
    v:dwpt::float as dew_point,
    v:rhum::float as relative_humidity,
    v:pres::float as pressure
from
    json_weather_data
where
    station_id = '72502';
--> v:[key名]を記載することで,Valueを取得

    
--> 作成したビューの確認
select * from json_weather_data_view
where date_trunc('month',observation_time) = '2018-01-01'
limit 20;


/* 7-6) Tripsデータと Weatherデータを結合  */
select weather_conditions as conditions
,count(*) as num_trips
from citibike.public.trips
left outer join json_weather_data_view
on date_trunc('hour', observation_time) = date_trunc('hour', starttime)
where conditions is not null
group by 1 order by 2 desc;
-- アメリカの方の特性が見られるかも?!



/*******************************************************************************
    8. タイムトラベル, ゼロクローンコピーの操作
*******************************************************************************/

/* 8-1-1) (誤って...)テーブルを削除  */

drop table json_weather_data;

--> ドロップされたか確認  ※エラー発生が正常
select * from json_weather_data limit 10;

/* 8-1-2) タイムトラベル：Undropコマンドでテーブルを復元  */
undrop table json_weather_data;

--> テーブルが復元されているかを確認
select * from json_weather_data limit 10;


-- これからクエリ実行するロール,ウェアハウス,データベース,スキーマを指定
use role sysadmin;
use warehouse compute_wh;
use database citibike;
use schema public;


/* 8-2-1) (意図的に誤って...) Update 処理を実行
          全てのステーション名を「oops」に変更  */
update trips set start_station_name = 'oops';

--> Update 結果の確認（乗車回数の上位20ステーションを確認するクエリを実行）
select
    start_station_name as "station"
    ,count(*) as "rides"
from trips
group by 1
order by 2 desc
limit 20;
    -- 結果が1行「oops」しか返ってこない


/* 8-2-2) Update 結果を戻すため、
          直近で実行された Update コマンドのクエリIDを検索し、
          変数 $QUERY_ID に格納 */

set query_id =
    (select query_id 
     from table(information_schema.query_history_by_session (result_limit=>10))
     where query_text like 'update%'
     order by start_time desc limit 1);

Select $query_id;
     
/* 8-2-3) タイムトラベル：Update前の状態でテーブルを再作成 */
create or replace table trips as
(select * from trips before (statement => $query_id));

--> 再作成したテーブルでステーション名が復元されているか確認
select
    start_station_name as "station"
    ,count(*) as "rides"
from trips
group by 1
order by 2 desc
limit 20;


/* 8-0) 本番稼働後は,本番テーブル「Trips」で開発するのは基本NG!!
        よって,開発用のテーブル「Trips_dev」を作成 */
create table trips_dev clone trips;

--> ゼロコピークローン：ポインターがコピーされるだけで,実体はコピーされない


/*******************************************************************************
    9. ロール、Accountadmin、およびアカウントの使用状況の操作
*******************************************************************************/

-- これからクエリ実行するロール「AccountAdmin」を指定
use role accountadmin;


-- 新しいロール Junior_DBA を作成し、自分に割り当て
create role junior_dba;
grant role junior_dba to user ysakuragi;


-- 作成、割り当てした Junior_DBA へ変更 -> ウェアハウスやデータベースの使用権限を確認
use role junior_dba;

-- Accountadmin へ変更し、compute_wh の使用権限を Junior_DBA へ付与

use role accountadmin;
grant usage on warehouse compute_wh to role junior_dba;

-- Junior_DBA へ変更し、使用できるウェアハウスを確認

use role junior_dba;
use warehouse compute_wh;

-- Accountadmin へ変更し、CITIBIKE, Weather データベースの使用権限を Junior_DBA へ付与

use role accountadmin;
grant usage on database citibike to role junior_dba;
grant usage on database weather to role junior_dba;

-- Junior_DBA へ変更し、使用できるデータベースを確認

use role junior_dba;


/*******************************************************************************
    11. Snowflake 環境のリセット
*******************************************************************************/

-- Accountadmin を使用して、今回作成した全てのオブジェクトを削除

use role accountadmin;

drop share if exists zero_to_snowflake_shared_data;
-- 必要に応じて、"zero_to_snowflake-shared_data" を共有に使用した名前に置き換え
drop database if exists citibike;
drop database if exists weather;
drop warehouse if exists analytics_wh;
drop warehouse if exists compute_wh;
drop role if exists junior_dba;
ALTER ACCOUNT SET USE_CACHED_RESULT = false;
ALTER ACCOUNT SET USE_CACHED_RESULT = true;
