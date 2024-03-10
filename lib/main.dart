// ignore_for_file: library_private_types_in_public_api

import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

part 'main.g.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Películas Populares',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const PopularMoviesPage(),
    );
  }
}

class DBHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }
    _database = await initDatabase();
    return _database!;
  }

  Future<Database> initDatabase() async {
    String dbPath = path.join(await getDatabasesPath(), 'movies.db');
    return await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE movies(
            id INTEGER PRIMARY KEY,
            title TEXT,
            overview TEXT,
            posterPath TEXT,
            isFavorite INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE reviews(
            id INTEGER PRIMARY KEY,
            movieId INTEGER,
            text TEXT,
            rating INTEGER
          )
        ''');
      },
    );
  }

  Future<void> insertMovie(Map<String, dynamic> movie) async {
    final Database db = await database;
    await db.insert('movies', movie,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertReview(Map<String, dynamic> review) async {
    final Database db = await database;
    await db.insert('reviews', review,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getReviewsForMovie(int movieId) async {
    final Database db = await database;
    return await db
        .query('reviews', where: 'movieId = ?', whereArgs: [movieId]);
  }
}

class PopularMoviesPage extends StatefulWidget {
  const PopularMoviesPage({Key? key}) : super(key: key);

  @override
  _PopularMoviesPageState createState() => _PopularMoviesPageState();
}

class _PopularMoviesPageState extends State<PopularMoviesPage> {
  List<Movie> movies = [];
  List<Movie> filteredMovies = [];
  bool _isLoading = false;
  final dbHelper = DBHelper();
  TextEditingController searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Películas Populares'),
        actions: [
          IconButton(
            onPressed: () {
              _filterMovies(searchController.text);
            },
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar películas',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (!_isLoading) {
                setState(() {
                  _isLoading = true;
                });
                fetchPopularMovies();
              }
            },
            child: const Text('Mostrarme'),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(),
                  )
                : ListView.builder(
                    itemCount: filteredMovies.length,
                    itemBuilder: (BuildContext context, int index) {
                      return MovieListItem(
                        movie: filteredMovies[index],
                        dbHelper: dbHelper, // Pasa el dbHelper aquí
                        onFavoriteChanged: () {
                          _filterMovies(searchController.text);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> fetchPopularMovies() async {
    final response = await http.get(
      Uri.parse(
          'https://api.themoviedb.org/3/movie/popular?api_key=dd9c5200c1cbc0ad07bc8e2534c75b6f&language=en-US&page=1'),
    );

    if (response.statusCode == 200) {
      final parsed = jsonDecode(response.body);
      setState(() {
        movies =
            List<Movie>.from(parsed['results'].map((x) => Movie.fromJson(x)));
        filteredMovies = List.from(movies);
        _isLoading = false;
      });
    } else {
      throw Exception('Failed to load movies');
    }
  }

  void _filterMovies(String query) {
    setState(() {
      filteredMovies = movies
          .where((movie) =>
              movie.title.toLowerCase().contains(query.toLowerCase()) &&
              movie.isFavorite) // Filtra las películas que sean favoritas
          .toList();
    });
  }
}

@JsonSerializable()
class Movie {
  final int id;
  final String title;
  final String overview;
  @JsonKey(name: 'poster_path')
  final String posterPath;
  bool isFavorite;

  Movie({
    required this.id,
    required this.title,
    required this.overview,
    required this.posterPath,
    this.isFavorite = false,
  });

  factory Movie.fromJson(Map<String, dynamic> json) => _$MovieFromJson(json);
}

class MovieListItem extends StatefulWidget {
  final Movie movie;
  final DBHelper dbHelper;
  final VoidCallback? onFavoriteChanged;

  const MovieListItem({
    Key? key,
    required this.movie,
    required this.dbHelper,
    this.onFavoriteChanged,
  }) : super(key: key);

  @override
  _MovieListItemState createState() => _MovieListItemState();
}

class _MovieListItemState extends State<MovieListItem> {
  bool _expanded = false;
  final TextEditingController _reviewController = TextEditingController();
  int _rating = 1;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Image.network(
        'https://image.tmdb.org/t/p/w185${widget.movie.posterPath}',
        width: 100,
      ),
      title: Text(widget.movie.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(!_expanded && widget.movie.overview.length > 50
              ? '${widget.movie.overview.substring(0, 50)}...'
              : widget.movie.overview),
          if (_expanded) ...[
            const SizedBox(height: 8),
            Text('Reseñas:', style: Theme.of(context).textTheme.titleMedium),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: widget.dbHelper.getReviewsForMovie(widget.movie.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const CircularProgressIndicator();
                } else if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                } else {
                  final reviews = snapshot.data!;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: reviews.map((review) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(review['text']),
                            Text('Rating: ${review['rating']}'),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _reviewController,
              decoration: const InputDecoration(
                labelText: 'Tu reseña',
              ),
            ),
            Row(
              children: [
                const Text('Rating: '),
                DropdownButton<int>(
                  value: _rating,
                  onChanged: (int? value) {
                    setState(() {
                      _rating = value!;
                    });
                  },
                  items: List.generate(
                    5,
                    (index) => DropdownMenuItem<int>(
                      value: index + 1,
                      child: Text((index + 1).toString()),
                    ),
                  ),
                ),
              ],
            ),
            ElevatedButton(
              onPressed: () {
                _addReview();
              },
              child: const Text('Agregar reseña'),
            ),
          ],
        ],
      ),
      trailing: _buildFavoriteButton(),
    );
  }

  Widget _buildFavoriteButton() {
    return IconButton(
      icon: Icon(
        widget.movie.isFavorite ? Icons.favorite : Icons.favorite_border,
        color: widget.movie.isFavorite ? Colors.red : null,
      ),
      onPressed: () {
        setState(() {
          widget.movie.isFavorite = !widget.movie.isFavorite;
          widget.dbHelper.insertMovie({
            'id': widget.movie.id,
            'title': widget.movie.title,
            'overview': widget.movie.overview,
            'posterPath': widget.movie.posterPath,
            'isFavorite': widget.movie.isFavorite ? 1 : 0,
          });
          if (widget.onFavoriteChanged != null) {
            widget.onFavoriteChanged!();
          }
        });
      },
    );
  }

  void _addReview() async {
    await widget.dbHelper.insertReview({
      'movieId': widget.movie.id,
      'text': _reviewController.text,
      'rating': _rating,
    });
    setState(() {
      _expanded = false;
      _reviewController.clear();
      _rating = 1;
    });
  }
}
